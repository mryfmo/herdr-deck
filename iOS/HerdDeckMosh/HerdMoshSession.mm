#import "HerdMoshSession.h"

#include <mosh/moshiosbridge.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

@interface HerdMoshSession () {
    NSString *_host;
    NSString *_key;
    NSString *_predictionMode;
    int32_t _port;
    struct winsize _windowSize;
    struct winsize *_activeWindowSize;
    int _inputPipe[2];
    int _outputPipe[2];
    FILE *_inputFile;
    FILE *_outputFile;
    dispatch_queue_t _engineQueue;
    dispatch_queue_t _readerQueue;
    HerdMoshOutputHandler _outputHandler;
    HerdMoshExitHandler _exitHandler;
    NSData *_encodedState;
    pthread_t _moshThread;
    BOOL _hasMoshThread;
    BOOL _running;
    BOOL _stopping;
}

- (void)acceptEncodedState:(const void *)buffer size:(size_t)size;
@end

static void HerdMoshStateCallback(const void *context, const void *buffer, size_t size) {
    if (context == NULL || buffer == NULL || size == 0) return;
    HerdMoshSession *session = (__bridge HerdMoshSession *)context;
    [session acceptEncodedState:buffer size:size];
}

@implementation HerdMoshSession

- (instancetype)initWithHost:(NSString *)host
                         port:(int32_t)port
                          key:(NSString *)key
               predictionMode:(NSString *)predictionMode
                      columns:(int32_t)columns
                         rows:(int32_t)rows
                outputHandler:(HerdMoshOutputHandler)outputHandler
                  exitHandler:(HerdMoshExitHandler)exitHandler {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _key = [key copy];
        _predictionMode = [predictionMode copy];
        _outputHandler = [outputHandler copy];
        _exitHandler = [exitHandler copy];
        _windowSize = {};
        _windowSize.ws_col = (unsigned short)MAX(20, MIN(columns, 500));
        _windowSize.ws_row = (unsigned short)MAX(6, MIN(rows, 300));
        _inputPipe[0] = _inputPipe[1] = -1;
        _outputPipe[0] = _outputPipe[1] = -1;
        _engineQueue = dispatch_queue_create("com.herddeck.mosh.engine", DISPATCH_QUEUE_SERIAL);
        _readerQueue = dispatch_queue_create("com.herddeck.mosh.output", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)start {
    @synchronized (self) {
        if (_running) return;
        _running = YES;
        _stopping = NO;
    }

    if (pipe(_inputPipe) != 0 || pipe(_outputPipe) != 0) {
        @synchronized (self) { _running = NO; }
        dispatch_async(dispatch_get_main_queue(), ^{ self->_exitHandler(71); });
        return;
    }
    _inputFile = fdopen(_inputPipe[0], "r");
    _outputFile = fdopen(_outputPipe[1], "w");
    if (_inputFile == NULL || _outputFile == NULL) {
        [self closeDescriptors];
        @synchronized (self) { _running = NO; }
        dispatch_async(dispatch_get_main_queue(), ^{ self->_exitHandler(72); });
        return;
    }
    setvbuf(_outputFile, NULL, _IONBF, 0);

    dispatch_async(_readerQueue, ^{
        uint8_t buffer[8192];
        while (true) {
            ssize_t count = read(self->_outputPipe[0], buffer, sizeof(buffer));
            if (count <= 0) break;
            NSData *data = [NSData dataWithBytes:buffer length:(NSUInteger)count];
            dispatch_async(dispatch_get_main_queue(), ^{ self->_outputHandler(data); });
        }
    });

    dispatch_async(_engineQueue, ^{
        struct winsize windowSize;
        @synchronized (self) {
            windowSize = self->_windowSize;
            self->_activeWindowSize = &windowSize;
            self->_moshThread = pthread_self();
            self->_hasMoshThread = YES;
        }
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        const char *lang = getenv("LANG");
        if (lang == NULL || strstr(lang, "UTF-8") == NULL) setenv("LANG", "en_US.UTF-8", 1);

        NSString *portString = [NSString stringWithFormat:@"%d", self->_port];
        NSData *resumeState = self->_encodedState;
        const char *stateBytes = resumeState.length > 0 ? (const char *)resumeState.bytes : "";
        int result = mosh_main(
            self->_inputFile,
            self->_outputFile,
            &windowSize,
            HerdMoshStateCallback,
            (__bridge const void *)self,
            self->_host.UTF8String,
            portString.UTF8String,
            self->_key.UTF8String,
            self->_predictionMode.UTF8String,
            stateBytes,
            resumeState.length,
            "no"
        );

        @synchronized (self) {
            self->_activeWindowSize = NULL;
            self->_hasMoshThread = NO;
            self->_running = NO;
        }
        [self closeDescriptors];
        dispatch_async(dispatch_get_main_queue(), ^{ self->_exitHandler((int32_t)result); });
    });
}

- (void)write:(NSData *)data {
    if (data.length == 0 || _inputPipe[1] < 0) return;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(_inputPipe[1], bytes, remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
}

- (void)resizeWithColumns:(int32_t)columns rows:(int32_t)rows {
    @synchronized (self) {
        _windowSize.ws_col = (unsigned short)MAX(20, MIN(columns, 500));
        _windowSize.ws_row = (unsigned short)MAX(6, MIN(rows, 300));
        if (_activeWindowSize != NULL) *_activeWindowSize = _windowSize;
        if (_hasMoshThread) pthread_kill(_moshThread, SIGWINCH);
    }
}

- (void)stop {
    @synchronized (self) {
        if (!_running || _stopping) return;
        _stopping = YES;
    }
    const uint8_t quit[] = { 0x1e, '.' };
    [self write:[NSData dataWithBytes:quit length:sizeof(quit)]];
    if (_inputPipe[1] >= 0) {
        close(_inputPipe[1]);
        _inputPipe[1] = -1;
    }
}

- (void)acceptEncodedState:(const void *)buffer size:(size_t)size {
    NSData *state = [NSData dataWithBytes:buffer length:size];
    @synchronized (self) { _encodedState = state; }
}

- (void)closeDescriptors {
    @synchronized (self) {
        if (_inputFile != NULL) {
            fclose(_inputFile);
            _inputFile = NULL;
            _inputPipe[0] = -1;
        } else if (_inputPipe[0] >= 0) {
            close(_inputPipe[0]);
            _inputPipe[0] = -1;
        }
        if (_inputPipe[1] >= 0) {
            close(_inputPipe[1]);
            _inputPipe[1] = -1;
        }
        if (_outputFile != NULL) {
            fclose(_outputFile);
            _outputFile = NULL;
            _outputPipe[1] = -1;
        } else if (_outputPipe[1] >= 0) {
            close(_outputPipe[1]);
            _outputPipe[1] = -1;
        }
        if (_outputPipe[0] >= 0) {
            close(_outputPipe[0]);
            _outputPipe[0] = -1;
        }
    }
}

@end
