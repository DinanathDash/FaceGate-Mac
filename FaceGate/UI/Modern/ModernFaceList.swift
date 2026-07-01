import SwiftUI

struct ModernFaceList: View {
    @Binding var enrolledFaces: [FaceEnrollment.EnrolledFace]
    @Binding var faceNames: [UUID: String]
    var renameFace: (UUID, String) -> Void
    var deleteFace: (UUID) -> Void
    var deleteAllFaceData: () -> Void
    @Binding var showFaceEnrollment: Bool
    @Binding var isAddingFace: Bool

    @State private var hoveredFace: UUID?
    @FocusState private var focusedFace: UUID?
    @State private var faceToDelete: UUID?
    @State private var showDeleteFaceAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enrolled Faces (Max 3)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 4)

            HStack {
                Spacer()
                HStack(alignment: .top, spacing: 24) {
                    ForEach(enrolledFaces) { face in
                        VStack(spacing: 4) {
                            ZStack(alignment: .topLeading) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 44, weight: .light))
                                    .foregroundColor(.gray)
                                    .frame(width: 50, height: 50)

                                if hoveredFace == face.id {
                                    Button(action: {
                                        faceToDelete = face.id
                                        showDeleteFaceAlert = true
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .background(Circle().fill(Color.black))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: -6, y: -6)
                                }
                            }
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredFace = face.id
                                } else if hoveredFace == face.id {
                                    hoveredFace = nil
                                }
                            }

                            let faceIndex = enrolledFaces.firstIndex(where: { $0.id == face.id }) ?? 0
                            let defaultName = "Face \(faceIndex + 1)"
                            let currentName = faceNames[face.id] ?? face.name
                            let isDefault = currentName == defaultName
                            
                            MacCenteredTextField(
                                text: Binding(
                                    get: { (isDefault || faceNames[face.id]?.isEmpty == true) ? "" : currentName },
                                    set: { newValue in
                                        faceNames[face.id] = newValue
                                        if !newValue.isEmpty {
                                            renameFace(face.id, newValue)
                                        }
                                    }
                                ),
                                placeholder: defaultName,
                                onCommit: {
                                    if faceNames[face.id]?.isEmpty == true {
                                        faceNames[face.id] = defaultName
                                        renameFace(face.id, defaultName)
                                    }
                                }
                            )
                            .frame(width: 80, height: 20)
                        }
                    }

                    if enrolledFaces.count < 3 {
                        VStack(spacing: 4) {
                            Button(action: {
                                isAddingFace = true
                                showFaceEnrollment = true
                            }) {
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .light))
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, height: 50)
                                    .background(Circle().fill(Color.white.opacity(0.05)))
                            }
                            .buttonStyle(.plain)

                            Text("Add Face")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 80, height: 20)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .alert("Delete Face", isPresented: $showDeleteFaceAlert, presenting: faceToDelete) { faceId in
                Button("Cancel", role: .cancel) {
                    faceToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    deleteFace(faceId)
                    faceToDelete = nil
                }
            } message: { faceId in
                if let face = enrolledFaces.first(where: { $0.id == faceId }) {
                    let currentName = faceNames[face.id] ?? face.name
                    Text("Are you sure you want to delete '\(currentName)'? This action cannot be undone.")
                } else {
                    Text("Are you sure you want to delete this face? This action cannot be undone.")
                }
            }
            .onChangeCompat(of: focusedFace) { newFocus in
                if newFocus == nil {
                    for (index, face) in enrolledFaces.enumerated() {
                        if faceNames[face.id]?.isEmpty == true {
                            let defaultName = "Face \(index + 1)"
                            faceNames[face.id] = defaultName
                            renameFace(face.id, defaultName)
                        }
                    }
                }
            }
        }
    }
}
