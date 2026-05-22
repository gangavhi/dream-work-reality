import XCTest
@testable import DreamWorkApp

final class ZeroEgressPolicyTests: XCTestCase {
    func testAllowsLoopbackOllama() {
        XCTAssertTrue(ZeroEgressPolicy.allowsLLMEndpoint("http://127.0.0.1:11434/v1"))
        XCTAssertTrue(ZeroEgressPolicy.allowsLLMEndpoint("http://localhost:11434/v1"))
    }

    func testAllowsPrivateLAN() {
        XCTAssertTrue(ZeroEgressPolicy.allowsLLMEndpoint("http://192.168.1.42:11434/v1"))
        XCTAssertTrue(ZeroEgressPolicy.allowsLLMEndpoint("http://10.0.0.5:1234/v1"))
        XCTAssertTrue(ZeroEgressPolicy.allowsLLMEndpoint("http://172.16.0.1:8080/v1"))
    }

    func testAllowsBonjourLocalHost() {
        XCTAssertTrue(ZeroEgressPolicy.allowsLLMEndpoint("http://kota-macbook.local:11434/v1"))
    }

    func testBlocksPublicInternetHost() {
        XCTAssertFalse(ZeroEgressPolicy.allowsLLMEndpoint("https://api.openai.com/v1"))
        XCTAssertFalse(ZeroEgressPolicy.allowsLLMEndpoint("https://example.com/v1"))
    }

    func testCoreAPIRequiresLoopback() {
        let localhost = URL(string: "http://127.0.0.1:18081")!
        let lan = URL(string: "http://192.168.1.1:18081")!
        XCTAssertTrue(ZeroEgressPolicy.allowsCoreAPILocalhost(localhost))
        XCTAssertFalse(ZeroEgressPolicy.allowsCoreAPILocalhost(lan))
    }

    func testSanitizedProviderRemovesCloudInReleaseConfiguration() {
        let previous = UserDefaults.standard.bool(forKey: "dreamwork.zero_egress.allow_cloud_llm_dev")
        defer { UserDefaults.standard.set(previous, forKey: "dreamwork.zero_egress.allow_cloud_llm_dev") }

        UserDefaults.standard.set(false, forKey: "dreamwork.zero_egress.allow_cloud_llm_dev")
        XCTAssertEqual(ZeroEgressPolicy.sanitizedProvider(.cloudLLMDevOnly), .off)
        XCTAssertEqual(ZeroEgressPolicy.sanitizedProvider(.localLLM), .localLLM)
    }

    func testGenAISettingsDefaultProviderIsOnDevice() {
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
        XCTAssertEqual(GenAISettings.provider, .onDevice)
    }

    func testActiveLLMConfigNilWhenProviderOff() {
        let providerKey = "dreamwork.genai.provider"
        let previous = UserDefaults.standard.string(forKey: providerKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: providerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: providerKey)
            }
        }
        GenAISettings.provider = .off
        XCTAssertNil(GenAISettings.activeLLMConfig)
    }

    func testActiveLLMConfigBlocksPublicURLEvenForLocalProvider() {
        let providerKey = "dreamwork.genai.provider"
        let baseURLKey = "dreamwork.genai.base_url"
        let previousProvider = UserDefaults.standard.string(forKey: providerKey)
        let previousBase = UserDefaults.standard.string(forKey: baseURLKey)
        defer {
            if let previousProvider {
                UserDefaults.standard.set(previousProvider, forKey: providerKey)
            } else {
                UserDefaults.standard.removeObject(forKey: providerKey)
            }
            if let previousBase {
                UserDefaults.standard.set(previousBase, forKey: baseURLKey)
            } else {
                UserDefaults.standard.removeObject(forKey: baseURLKey)
            }
        }

        GenAISettings.provider = .localLLM
        GenAISettings.baseURL = "https://api.openai.com/v1"
        XCTAssertNil(GenAISettings.activeLLMConfig)
    }
}
