import XCTest
@testable import DreamWorkApp

final class ZeroEgressPolicyTests: XCTestCase {
    func testBlocksAllLLMHTTPEndpoints() {
        XCTAssertFalse(ZeroEgressPolicy.allowsLLMEndpoint("http://127.0.0.1:11434/v1"))
        XCTAssertFalse(ZeroEgressPolicy.allowsLLMEndpoint("http://192.168.1.42:11434/v1"))
        XCTAssertFalse(ZeroEgressPolicy.allowsLLMEndpoint("https://api.openai.com/v1"))
    }

    func testCoreAPIRequiresLoopback() {
        let localhost = URL(string: "http://127.0.0.1:18081")!
        let lan = URL(string: "http://192.168.1.1:18081")!
        XCTAssertTrue(ZeroEgressPolicy.allowsCoreAPILocalhost(localhost))
        XCTAssertFalse(ZeroEgressPolicy.allowsCoreAPILocalhost(lan))
    }

    func testMigratesLegacyGGUFProviderToAppleNative() {
        let providerKey = "dreamwork.genai.provider"
        let previous = UserDefaults.standard.string(forKey: providerKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: providerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: providerKey)
            }
        }
        UserDefaults.standard.set("On-device GGUF", forKey: providerKey)
        XCTAssertEqual(GenAISettings.provider, .appleNative)
    }

    func testGenAISettingsDefaultProviderIsAppleNative() {
        let providerKey = "dreamwork.genai.provider"
        let previous = UserDefaults.standard.string(forKey: providerKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: providerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: providerKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: providerKey)
        XCTAssertEqual(GenAISettings.provider, .appleNative)
    }

    func testActiveLLMConfigNilForAppleNativeProviders() {
        let previous = GenAISettings.provider
        defer { GenAISettings.provider = previous }
        GenAISettings.provider = .appleNative
        XCTAssertNil(GenAISettings.activeLLMConfig)
        GenAISettings.provider = .off
        XCTAssertNil(GenAISettings.activeLLMConfig)
    }
}
