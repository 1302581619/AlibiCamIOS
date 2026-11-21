import Foundation
import Combine

/// 全局状态容器：持有设置与录像引擎
final class AppState: ObservableObject {
    let settings = Settings()
    lazy var engine: RecorderEngine = RecorderEngine(settings: self.settings)
}
