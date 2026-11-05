/// System privacy permissions a feature may need. Core shows them in onboarding/settings
/// for enabled features (stage 3).
public enum Permission: String, Hashable, Sendable, CaseIterable {
    case screenRecording
    case accessibility
}
