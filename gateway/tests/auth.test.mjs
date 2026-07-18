import assert from 'node:assert/strict';
import test from 'node:test';
import { SlidingWindowRateLimiter, constantTimeEqual } from '../src/auth.mjs';

test('constantTimeEqual accepts only exact token matches', () => {
  assert.equal(constantTimeEqual('abc123', 'abc123'), true);
  assert.equal(constantTimeEqual('abc123', 'abc124'), false);
  assert.equal(constantTimeEqual('abc123', 'abc1234'), false);
  assert.equal(constantTimeEqual('abc123', null), false);
});

test('SlidingWindowRateLimiter enforces and resets a window', () => {
  const limiter = new SlidingWindowRateLimiter({ windowMs: 1000, maxRequests: 2 });
  assert.equal(limiter.allow('client', 1000), true);
  assert.equal(limiter.allow('client', 1100), true);
  assert.equal(limiter.allow('client', 1200), false);
  assert.equal(limiter.allow('client', 2101), true);
});
