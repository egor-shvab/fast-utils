import SwiftUI

/// Rows with status and a "Grant" button for each permission. Watches statuses while visible.
struct PermissionsList: View {
    let permissions: [Permission]
    let service: PermissionsService

    var body: some View {
        ForEach(permissions, id: \.self) { permission in
            PermissionRow(permission: permission, service: service)
        }
        .onAppear { service.startWatching() }
        .onDisappear { service.stopWatching() }
    }
}

struct PermissionRow: View {
    let permission: Permission
    let service: PermissionsService

    var body: some View {
        let status = service.status(of: permission)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.icon)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.body.weight(.medium))
                Text(permission.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            switch status {
            case .granted:
                Label(String(localized: "permission.status.granted"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            case .notGranted:
                Button(String(localized: "permission.action.grant")) { service.request(permission) }
            case .denied:
                Button(String(localized: "permission.action.openSettings")) { service.openSettings(for: permission) }
            }
        }
        .padding(.vertical, 4)
    }
}
