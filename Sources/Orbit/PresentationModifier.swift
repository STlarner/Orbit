import SwiftUI

@MainActor
struct PresentationModifier: ViewModifier {
    let context: OrbitContext

    func body(content: Content) -> some View {
        let id = context.presentation?.id
        let sheet = content.sheet(
            item: binding(for: .sheet),
            onDismiss: { if let id { context.completeDismiss(id: id) } }
        ) { state in
            presentedContent(state)
        }
        #if os(iOS)
        sheet.fullScreenCover(
            item: binding(for: .fullScreen),
            onDismiss: { if let id { context.completeDismiss(id: id) } }
        ) { state in
            presentedContent(state)
        }
        #else
        sheet
        #endif
    }

    private func binding(
        for style: OrbitPresentationStyle
    ) -> Binding<PresentationState?> {
        Binding(
            get: {
                guard let state = context.presentation,
                    state.style == style, state.isPresented
                else { return nil }
                return state
            },
            set: { value in
                guard value == nil, let state = context.presentation,
                    state.style == style
                else { return }
                context.requestDismiss(id: state.id)
            }
        )
    }

    private func presentedContent(_ state: PresentationState) -> some View {
        FlowContent(route: state.route, context: state.context)
            .environment(\.orbit, state.context)
            .modifier(PresentationModifier(context: state.context))
    }
}
