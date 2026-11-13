import AppModels
import Foundation
import Testing

// `lanraragiServerURL` was added after schema v2 without a bump, so a blob written before it must keep
// decoding, with no server, rather than reset every other preference.
struct SettingLANraragiServerTests {
    private static func customizedSetting() -> Setting {
        var setting = Setting()
        setting.galleryHost = .exhentai
        setting.prefetchLimit = 42
        return setting
    }

    private static func jsonObject(_ setting: Setting) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(setting)) as? [String: Any])
    }

    private static func decode(_ object: [String: Any]) throws -> Setting {
        try JSONDecoder().decode(Setting.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test
    func aBlobWithoutTheServerDecodesWithNoServer() throws {
        var object = try Self.jsonObject(Self.customizedSetting())
        object.removeValue(forKey: "lanraragiServerURL")

        let decoded = try Self.decode(object)

        #expect(decoded.lanraragiServerURL.isEmpty)
        #expect(decoded == Self.customizedSetting())
    }

    @Test
    func theServerRoundTrips() throws {
        var setting = Self.customizedSetting()
        setting.lanraragiServerURL = "http://192.168.1.2:3000"

        let object = try Self.jsonObject(setting)

        #expect(object["lanraragiServerURL"] as? String == "http://192.168.1.2:3000")
        #expect(try Self.decode(object) == setting)
    }
}
