import XCTest
@testable import HerdDeck

final class ModelDecodingTests: XCTestCase {
    func testSnapshotDecodesUnknownAgentStatusSafely() throws {
        let json = #"""
        {
          "snapshot": {
            "version": "0.10.0",
            "protocol": 1,
            "focused_workspace_id": null,
            "focused_tab_id": null,
            "focused_pane_id": "p1",
            "workspaces": [],
            "tabs": [],
            "panes": [],
            "layouts": [],
            "agents": [
              {
                "terminal_id": "t1",
                "name": "builder",
                "agent": "codex",
                "title": null,
                "display_agent": "Codex",
                "agent_status": "future_state",
                "screen_detection_skipped": false,
                "custom_status": null,
                "state_labels": {},
                "agent_session": null,
                "workspace_id": "w1",
                "tab_id": "tab1",
                "pane_id": "p1",
                "focused": true,
                "cwd": "/tmp/project",
                "foreground_cwd": "/tmp/project",
                "revision": 1
              }
            ]
          }
        }
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SnapshotResponse.self, from: json)
        XCTAssertEqual(response.snapshot.agents.first?.agentStatus, .unknown)
    }

    func testAgmsgMessageMapsWireIdentityFields() throws {
        let json = #"{"type":"message_sent","id":"42","team":"alpha","from":"orchestrator","to":"builder","body":"ship it","at":"2026-07-12T00:00:00Z"}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(AgmsgMessage.self, from: json)
        XCTAssertEqual(value.fromAgent, "orchestrator")
        XCTAssertEqual(value.toAgent, "builder")
        XCTAssertEqual(value.id, "42")
    }

    func testTerminalInputMapperHandlesUnicodeAndControlKeys() {
        let mapped = TerminalInputMapper.map(Data("日本語🙂".utf8))
        XCTAssertEqual(mapped, [TerminalMappedInput(text: "日本語🙂")])

        XCTAssertEqual(
            TerminalInputMapper.map(Data([0x1b, 0x5b, 0x41])),
            [TerminalMappedInput(keys: ["up"])]
        )
        XCTAssertEqual(
            TerminalInputMapper.map(Data(Array("A🙂".utf8) + [0x1b, 0x5b, 0x43, 0x03])),
            [TerminalMappedInput(text: "A🙂"), TerminalMappedInput(keys: ["right", "ctrl+c"])]
        )
        XCTAssertEqual(
            Array(TerminalInputMapper.encode(keys: ["ctrl+c", "left", "enter"])),
            [0x03, 0x1b, 0x5b, 0x44, 0x0d]
        )
    }

    func testTerminalInputMapperDropsUnknownEscapeSequencesAndPreservesOrder() {
        XCTAssertTrue(TerminalInputMapper.map(Data("\u{1b}[<35;10;5M".utf8)).isEmpty)
        XCTAssertTrue(TerminalInputMapper.map(Data("\u{1b}OA".utf8)).isEmpty)
        XCTAssertEqual(
            TerminalInputMapper.map(Data("\u{1b}[200~paste\u{1b}[201~".utf8)),
            [TerminalMappedInput(text: "paste")]
        )
        XCTAssertEqual(
            TerminalInputMapper.map(Data("a\nb\nc".utf8)),
            [
                TerminalMappedInput(text: "a"),
                TerminalMappedInput(keys: ["enter"]),
                TerminalMappedInput(text: "b"),
                TerminalMappedInput(keys: ["enter"]),
                TerminalMappedInput(text: "c"),
            ]
        )
        XCTAssertTrue(
            TerminalInputMapper.map(Data(String(repeating: "\n", count: 33).utf8))
                .allSatisfy { $0.keys.count <= 32 }
        )
    }

    func testAgentStartedResponseDecodesGatewaySlimAgentWithoutArgv() throws {
        let json = #"{"type":"agent_started","agent":{"pane_id":"p1","terminal_id":"t1"}}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(AgentStartedResponse.self, from: json)
        XCTAssertEqual(response.agent.paneId, "p1")
        XCTAssertEqual(response.agent.terminalId, "t1")
        XCTAssertNil(response.argv)
    }

    func testRichOutputParserRecognizesMarkdownBlocksAndEmoji() {
        let blocks = RichOutputParser.parse(
            """
            # 結果 🚀

            - テスト成功 ✅

            ```swift
            print("こんにちは")
            ```

            | 項目 | 状態 |
            | --- | --- |
            | Build | OK |
            """
        )
        XCTAssertTrue(blocks.contains(.heading(level: 1, text: "結果 🚀")))
        XCTAssertTrue(blocks.contains(.listItem(marker: "•", text: "テスト成功 ✅")))
        XCTAssertTrue(blocks.contains(.code(language: "swift", text: "print(\"こんにちは\")")))
        XCTAssertTrue(blocks.contains(.table([["項目", "状態"], ["Build", "OK"]])))
    }

    func testTerminalPreferencesRoundTrip() throws {
        let value = TerminalUserPreferences(
            transportPolicy: .automatic,
            renderMode: .rich,
            moshPredictionMode: "adaptive",
            cellularHysteresisSeconds: 60
        )
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(TerminalUserPreferences.self, from: data), value)
    }

    func testGatewayRequestsEncodeCamelCase() throws {
        let request = MoshSessionRequest(
            paneId: "w1:p2",
            columns: 100,
            rows: 34,
            predictionMode: "adaptive"
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: GatewayJSONCoding.makeEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["paneId"] as? String, "w1:p2")
        XCTAssertNil(object["pane_id"])
        XCTAssertEqual(object["predictionMode"] as? String, "adaptive")
    }
}
