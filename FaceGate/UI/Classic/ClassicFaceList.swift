import SwiftUI

struct ClassicFaceList: View {
    @Binding var enrolledFaces: [FaceEnrollment.EnrolledFace]
    @Binding var faceNames: [UUID: String]
    var renameFace: (UUID, String) -> Void
    var deleteFace: (UUID) -> Void
    var deleteAllFaceData: () -> Void
    @Binding var showFaceEnrollment: Bool
    @Binding var isAddingFace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enrolled Faces (Max 3)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 4)

            ForEach(enrolledFaces) { face in
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                    
                    // Inline rename TextField
                    TextField("Face Name", text: Binding(
                        get: { faceNames[face.id] ?? face.name },
                        set: { faceNames[face.id] = $0 }
                    ), onEditingChanged: { isEditing in
                        if !isEditing {
                            if let name = faceNames[face.id] {
                                renameFace(face.id, name)
                            }
                        }
                    }, onCommit: {
                        if let name = faceNames[face.id] {
                            renameFace(face.id, name)
                        }
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        deleteFace(face.id)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.04))
                .cornerRadius(6)
            }
            
            HStack {
                if enrolledFaces.count < 3 {
                    Button("Add Face") {
                        isAddingFace = true
                        showFaceEnrollment = true
                    }
                    .controlSize(.small)
                }
                
                Button("Re-enroll Fresh") {
                    isAddingFace = false
                    showFaceEnrollment = true
                }
                .controlSize(.small)

                Button("Delete All Face Data") {
                    deleteAllFaceData()
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }
}
