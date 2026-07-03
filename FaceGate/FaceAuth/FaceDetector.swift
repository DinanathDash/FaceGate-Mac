import CoreImage
import Foundation
import Vision

/// Detects faces in video frames using Apple's Vision framework.
/// Provides bounding boxes, quality assessment, and face cropping for the embedding pipeline.
final class FaceDetector {
    /// Checks if a detected face is within the central UI boundary.
    /// This enforces the user to align their face with the circular UI guide.
    private func isFaceCentered(_ observation: VNFaceObservation, tolerance: CGFloat = 0.15) -> Bool {
        let boundingBox = observation.boundingBox
        let isCenteredX = abs(boundingBox.midX - 0.5) <= tolerance
        let isCenteredY = abs(boundingBox.midY - 0.5) <= tolerance
        return isCenteredX && isCenteredY
    }

    /// Detect face rectangles in a pixel buffer.
    /// - Parameters:
    ///   - pixelBuffer: The video frame to analyze.
    ///   - completion: Returns an array of face observations found in the frame, and a boolean indicating if any off-center face was detected.
    func detectFaces(in pixelBuffer: CVPixelBuffer, completion: @escaping ([VNFaceObservation], Bool) -> Void) {
        let request = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard error == nil,
                  let results = request.results as? [VNFaceObservation] else {
                completion([], false)
                return
            }
            let validFaces = results.filter { self?.isFaceCentered($0) ?? false }
            let hasOffCenterFace = !results.isEmpty && validFaces.count < results.count
            completion(validFaces, hasOffCenterFace)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            completion([], false)
        }
    }

    /// Detect faces with quality scores — used during enrollment to filter poor frames.
    /// - Parameters:
    ///   - pixelBuffer: The video frame to analyze.
    ///   - completion: Returns face observations paired with quality scores (0.0–1.0), and a flag if off-center face was detected.
    func detectFacesWithQuality(in pixelBuffer: CVPixelBuffer, completion: @escaping ([(face: VNFaceObservation, quality: Float)], Bool) -> Void) {
        let faceRequest = VNDetectFaceRectanglesRequest()
        let qualityRequest = VNDetectFaceCaptureQualityRequest()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([faceRequest, qualityRequest])
        } catch {
            completion([], false)
            return
        }

        guard let faceResults = faceRequest.results else {
            completion([], false)
            return
        }

        // Quality results correspond to the same faces.
        let qualityResults = qualityRequest.results ?? []

        var combined: [(face: VNFaceObservation, quality: Float)] = []
        var hasOffCenterFace = false
        for (index, face) in faceResults.enumerated() {
            // Apply spatial filter to enforce UI constraints
            guard isFaceCentered(face) else { 
                hasOffCenterFace = true
                continue 
            }
            
            let quality: Float
            if index < qualityResults.count, let q = qualityResults[index].faceCaptureQuality {
                quality = Float(q)
            } else {
                quality = 0.5  // Default if quality unavailable
            }
            combined.append((face: face, quality: quality))
        }

        completion(combined, hasOffCenterFace)
    }

    /// Crop the detected face region from a pixel buffer, with padding for better embedding quality.
    /// - Parameters:
    ///   - pixelBuffer: The source video frame.
    ///   - observation: The face observation with the bounding box.
    ///   - padding: Fraction of face size to add as padding (default 20%).
    /// - Returns: A cropped CGImage of the face, or nil if cropping fails.
    func cropFace(from pixelBuffer: CVPixelBuffer, observation: VNFaceObservation, padding: CGFloat = 0.2) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = ciImage.extent.size

        // Convert normalized Vision coordinates (0–1, origin at bottom-left) to pixel coordinates.
        let boundingBox = observation.boundingBox
        var faceRect = CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: boundingBox.origin.y * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )

        // Add padding around the face.
        let padX = faceRect.width * padding
        let padY = faceRect.height * padding
        faceRect = faceRect.insetBy(dx: -padX, dy: -padY)

        // Clamp to image bounds.
        faceRect = faceRect.intersection(ciImage.extent)
        guard !faceRect.isEmpty else { return nil }

        let croppedCI = ciImage.cropped(to: faceRect)
        let context = CIContext()
        return context.createCGImage(croppedCI, from: croppedCI.extent)
    }
}
