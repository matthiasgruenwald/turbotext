import SwiftUI

struct MicrophoneFavoritesSectionView: View {
    @Bindable var store: MicrophoneFavoritesStore
    let availableDevices: [AudioInputDevice]

    private var favoriteDevices: [AudioInputDevice] {
        store.favoriteUIDs.map { uid in
            availableDevices.first(where: { $0.uid == uid })
                ?? AudioInputDevice(id: 0, name: uid, uid: uid)
        }
    }

    private var addableDevices: [AudioInputDevice] {
        availableDevices.filter { !store.favoriteUIDs.contains($0.uid) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Mikrofon")

            Toggle("macOS-Standard verwenden", isOn: $store.useSystemDefault)
                .toggleStyle(.switch)
                .controlSize(.small)

            Text("Wenn deaktiviert, wählt Blitztext automatisch das oberste verfügbare Mikrofon aus deiner Favoritenliste — unabhängig vom macOS-Systemstandard.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !store.useSystemDefault {
                if favoriteDevices.isEmpty {
                    Text("Keine Favoriten. Füge unten ein Mikrofon hinzu.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(favoriteDevices.enumerated()), id: \.element.uid) { index, device in
                            MicrophoneFavoriteRow(
                                device: device,
                                isFirst: index == 0,
                                isLast: index == favoriteDevices.count - 1,
                                onMoveUp: { store.moveUp(uid: device.uid) },
                                onMoveDown: { store.moveDown(uid: device.uid) },
                                onRemove: { store.removeFavorite(uid: device.uid) }
                            )
                        }
                    }
                }

                if !addableDevices.isEmpty {
                    HStack(spacing: 8) {
                        Text("Hinzufügen")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        Menu {
                            ForEach(addableDevices) { device in
                                Button(device.name) {
                                    store.addFavorite(uid: device.uid)
                                }
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue.opacity(0.7))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
        }
    }
}

private struct MicrophoneFavoriteRow: View {
    let device: AudioInputDevice
    let isFirst: Bool
    let isLast: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(device.name)
                .font(.system(size: 11))
                .lineLimit(1)

            Spacer()

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(SubtleButtonStyle())
            .disabled(isFirst)

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(SubtleButtonStyle())
            .disabled(isLast)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(SubtleButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
