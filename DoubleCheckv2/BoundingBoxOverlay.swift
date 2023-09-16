

import SwiftUI
import Vision

struct BoundingBoxOverlay: View {
    @EnvironmentObject var frameInfoStore: FrameInfoStore
    
    var frameSize: CGSize
    var recognizedObjects: [RecognizedObject]
    
    var labelFilter: String
    
    var filteredObjects: [RecognizedObject] {
        return recognizedObjects.filter { $0.label == labelFilter }
    }
    var cameraAspectRatio: Float
    var color: Color
    
    private func convertBoundingBox(_ boundingBox: CGRect) -> CGRect {
        let originX = boundingBox.origin.x * frameSize.width
        let originY = (1 - boundingBox.origin.y - boundingBox.size.height) * frameSize.height
        let width = boundingBox.size.width * frameSize.width
        let height = boundingBox.size.height * frameSize.height
        
        let offsetY: CGFloat = frameSize.height * (1 - CGFloat(cameraAspectRatio)) / 2
        
        return CGRect(x: originX, y: originY - offsetY, width: width, height: height)
    }
    
    private func updateFrameInfo(greenBox: CGRect, yellowBox: CGRect) {
        let greenBoxNormalized = CGRect(x: greenBox.origin.x / frameSize.width,
                                        y: greenBox.origin.y / frameSize.height,
                                        width: greenBox.width / frameSize.width,
                                        height: greenBox.height / frameSize.height)
        let yellowBoxNormalized = CGRect(x: yellowBox.origin.x / frameSize.width,
                                         y: yellowBox.origin.y / frameSize.height,
                                         width: yellowBox.width / frameSize.width,
                                         height: yellowBox.height / frameSize.height)
        frameInfoStore.updateCurrentFrame(["green": greenBoxNormalized, "yellow": yellowBoxNormalized])
    }


    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(filteredObjects) { filteredObject in
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color, lineWidth: 3)
                        .frame(width: convertBoundingBox(filteredObject.boundingBox).width,
                               height: convertBoundingBox(filteredObject.boundingBox).height)
                        .position(x: convertBoundingBox(filteredObject.boundingBox).midX,
                                  y: geometry.size.height - convertBoundingBox(filteredObject.boundingBox).midY)
                    
                    if labelFilter == "rez" {
                        // Green bounding box
                        let greenBoundingBoxWidth: CGFloat = 75
                        let greenBoundingBoxX = convertBoundingBox(filteredObject.boundingBox).midX - (convertBoundingBox(filteredObject.boundingBox).width / 2) - (greenBoundingBoxWidth / 2)
                        let greenBoxY = geometry.size.height - convertBoundingBox(filteredObject.boundingBox).midY
                        
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green, lineWidth: 3)
                            .frame(width: greenBoundingBoxWidth, height: convertBoundingBox(filteredObject.boundingBox).height)
                            .position(x: greenBoundingBoxX, y: geometry.size.height - convertBoundingBox(filteredObject.boundingBox).midY)
                            .onAppear {
                                let greenBoxNormalized = CGRect(x: greenBoundingBoxX / frameSize.width,
                                                                y: (geometry.size.height - convertBoundingBox(filteredObject.boundingBox).midY) / frameSize.height,
                                                                width: greenBoundingBoxWidth / frameSize.width,
                                                                height: convertBoundingBox(filteredObject.boundingBox).height / frameSize.height)
                                frameInfoStore.updateCurrentFrame(["green": greenBoxNormalized])
                                print("Green box coordinates: \(greenBoxNormalized)")
                            }
                        // Yellow bounding box
                        let yellowBoundingBoxWidth: CGFloat = 50
                        let yellowBoundingBoxX = greenBoundingBoxX - (yellowBoundingBoxWidth / 2) - (greenBoundingBoxWidth / 2)
                        let yellowBoxY = geometry.size.height - convertBoundingBox(filteredObject.boundingBox).midY
                        
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow, lineWidth: 3)
                            .frame(width: yellowBoundingBoxWidth, height: convertBoundingBox(filteredObject.boundingBox).height)
                            .position(x: yellowBoundingBoxX, y: geometry.size.height - convertBoundingBox(filteredObject.boundingBox).midY)
                        
                            .onAppear {
                                let yellowBoxNormalized = CGRect(x: yellowBoundingBoxX / frameSize.width,
                                                                 y: (geometry.size.height - convertBoundingBox(filteredObject.boundingBox).midY) / frameSize.height,
                                                                 width: yellowBoundingBoxWidth / frameSize.width,
                                                                 height: convertBoundingBox(filteredObject.boundingBox).height / frameSize.height)
                                frameInfoStore.updateCurrentFrame(["yellow": yellowBoxNormalized])
                                print("Yellow box coordinates: \(yellowBoxNormalized)")
                            }
                    }
                }
            }
        }
    }
}
