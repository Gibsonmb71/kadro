import SwiftUI

/// The Command Line Tools SDK does not ship SwiftUI's `StateMacro` plugin.
/// This wrapper keeps local view state backed by SwiftUI's available StateObject
/// machinery so the package can be type-checked without a full Xcode install.
@propertyWrapper
struct StateCompat<Value>: DynamicProperty {
    @StateObject private var box: StateCompatBox<Value>

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: StateCompatBox(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { box.value },
            set: { box.value = $0 }
        )
    }
}
final class StateCompatBox<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
