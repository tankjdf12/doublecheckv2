
// ContentView.swift
import SwiftUI
import CoreML
import Vision
import AVFoundation

// ContentView is the main view of app, which displays the camera preview and bounding boxes for recognized objects

struct ContentView: View {
    // Declare properties to hold the camera view model, camera aspect ratio, and model performance in frames per second (FPS)
    @StateObject private var cameraViewModel = CameraViewModel()
    @State private var cameraAspectRatio: Float = 1
    @State private var modelPerformanceFPS: Double = 0.0
    @EnvironmentObject var frameInfoStore: FrameInfoStore

    // Define the body of the view, which is a vertical stack (VStack) containing the camera preview and bounding box overlays
    init() {
        cameraViewModel.onPillCoordsUpdate = { [self] pillCoords in
            frameInfoStore.updatePillCoords(pillCoords: pillCoords)
        }



    }
    var body: some View {
        VStack {
            GeometryReader { geometry in
                ZStack {
                    // GeometryReader is used to calculate the size of the camera preview based on the width of the parent view
                    CameraPreview(cameraViewModel: cameraViewModel, cameraAspectRatio: cameraViewModel.cameraAspectRatio)
                        .frame(width: geometry.size.width, height: geometry.size.width / CGFloat(cameraAspectRatio))
                        .clipped()
                    // BoundingBoxOverlay is a custom view that displays bounding boxes for recognized rez objects
                    BoundingBoxOverlay(frameSize: CGSize(width: geometry.size.width, height: geometry.size.width / CGFloat(cameraAspectRatio)), recognizedObjects: cameraViewModel.recognizedObjects, labelFilter: "rez", cameraAspectRatio: cameraViewModel.cameraAspectRatio, color: Color.green)
                        .frame(width: geometry.size.width, height: geometry.size.width / CGFloat(cameraAspectRatio))
                        .clipped()
                    BoundingBoxOverlay(frameSize: CGSize(width: geometry.size.width, height: geometry.size.width / CGFloat(cameraAspectRatio)), recognizedObjects: cameraViewModel.pillObjects, labelFilter: "pill", cameraAspectRatio: cameraViewModel.cameraAspectRatio, color: Color.orange)
                        .frame(width: geometry.size.width, height: geometry.size.width / CGFloat(cameraAspectRatio))
                        .clipped()

                }
            }

            Spacer(minLength: 40)

            Spacer()
            Image("your_logo_image")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
            Spacer()
        }
        .padding(.horizontal, 40)
        
    }

}



// RecognizedObject is a struct that holds information about a detected object, including its label, confidence, and bounding box

struct RecognizedObject: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}


// CameraPreview is a UIViewRepresentable that wraps the AVCaptureVideoPreviewLayer to display the live camera feed in a SwiftUI view
struct CameraPreview: UIViewRepresentable {
    @ObservedObject var cameraViewModel: CameraViewModel
    var cameraAspectRatio: Float

    // Create a UIView to display the live camera feed
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        cameraViewModel.setupCamera { previewLayer in
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }
        return view
    }
    
    // Update the UIView when the view model or aspect ratio changes (empty implementation since the camera feed updates automatically)
    func updateUIView(_ uiView: UIView, context: Context) {
    }
}


// CameraViewModel is a class that manages the camera session, video output, and object recognition using Core ML and Vision frameworks
class CameraViewModel: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private var output = AVCaptureVideoDataOutput()
    private var request: VNCoreMLRequest?
    private var pillRequest: VNCoreMLRequest?
    var onPillCoordsUpdate: (([Int: [[CGFloat]]]) -> Void)?

    // Properties to store recognized objects and camera aspect ratio
    @Published var recognizedObjects: [RecognizedObject] = [] // Change the type here
    @Published var cameraAspectRatio: Float = 1
    @Published var pillObjects: [RecognizedObject] = []

    @Published var pillMiddlePoints: [Int: [[CGFloat]]] = [:]


    override init() {
        super.init()
        setupModel()
    }
    private var cameraSetupComplete = false
    
    // Convert input pixel buffer to grayscale pixel buffer
    func convertToGrayscale(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        
        let context = CIContext(options: nil)
        var outputPixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), kCVPixelFormatType_32ARGB, attrs, &outputPixelBuffer)
        
        guard let output = outputPixelBuffer, status == kCVReturnSuccess else {
            return nil
        }
        
        context.render(grayscale, to: output)
        return output
    }
    
    // Set up the camera session, configure the device, input, and output, and add a video preview layer
    func setupCamera(completion: @escaping (AVCaptureVideoPreviewLayer) -> Void) {
        guard !cameraSetupComplete else { return }
        cameraSetupComplete = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720
                
                let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInUltraWideCamera], mediaType: .video, position: .back)
                
                guard let device = deviceDiscoverySession.devices.first else { return }
                
                // Remove existing inputs
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                
                let input = try AVCaptureDeviceInput(device: device)
                self.session.addInput(input)
                
                self.output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
                self.output.alwaysDiscardsLateVideoFrames = true
                self.session.addOutput(self.output)
                
                let previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                previewLayer.videoGravity = .resizeAspectFill
                let connection = previewLayer.connection
                connection?.videoOrientation = .portrait
                connection?.automaticallyAdjustsVideoMirroring = false
                
                self.session.commitConfiguration()
                self.session.startRunning()
                
                DispatchQueue.main.async {
                    completion(previewLayer)
                }
                
                let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.max { a, b in
                    a.width * a.height < b.width * b.height
                }
                
                if let maxDimensions = maxDimensions {
                    DispatchQueue.main.async {
                        self.cameraAspectRatio = Float(maxDimensions.width) / Float(maxDimensions.height)
                    }
                }
            } catch {
                print("Error setting up the camera: \(error.localizedDescription)")
            }

        }


    }

    // Set up Core ML model and create VNCoreMLRequest for object detection
    private func setupModel() {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all

                let model = try VNCoreMLModel(for: April6_Rez_Quant_Alb_v7_tiny(configuration: config).model) // Change this line
                request = VNCoreMLRequest(model: model, completionHandler: handleDetection)


            request?.imageCropAndScaleOption = .centerCrop
        } catch {
            print("Error setting up the Core ML model: \(error.localizedDescription)")
        }
        do {
            let pillConfig = MLModelConfiguration()
            pillConfig.computeUnits = .all

            let pillModel = try VNCoreMLModel(for: April6_Pill_Quant_Alb_v7_tiny(configuration: pillConfig).model)
            pillRequest = VNCoreMLRequest(model: pillModel, completionHandler: handlePillDetection)
            pillRequest?.imageCropAndScaleOption = .centerCrop
        } catch {
            print("Error setting up the AprilConvPill model: \(error.localizedDescription)")
        }

    }
    
    private func handleDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }

        DispatchQueue.main.async {
            // Find the highest-confidence Rez object observation
            let highestConfidenceRezObservation = results.compactMap { observation -> (VNRecognizedObjectObservation, VNClassificationObservation)? in
                guard let rezObject = observation.labels.first(where: { $0.identifier == "rez" }) else { return nil }
                return (observation, rezObject)
            }.max { a, b in
                a.1.confidence < b.1.confidence
            }

            if let (observation, rezObject) = highestConfidenceRezObservation {
                let adjustedBoundingBoxHeight = observation.boundingBox.size.height * CGFloat(self.cameraAspectRatio)
                let adjustedBoundingBoxOriginY = (1 - observation.boundingBox.origin.y - observation.boundingBox.size.height) * CGFloat(self.cameraAspectRatio)

                // Apply the downscaling factor to the bounding box
                let downscalingFactor: CGFloat = 0.8
                let downscaledWidth = observation.boundingBox.size.width * downscalingFactor
                let downscaledHeight = adjustedBoundingBoxHeight * downscalingFactor
                let downscaledOriginX = observation.boundingBox.origin.x + (observation.boundingBox.size.width - downscaledWidth) / 2
                let downscaledOriginY = adjustedBoundingBoxOriginY + (adjustedBoundingBoxHeight - downscaledHeight) / 2

                let downscaledBoundingBox = CGRect(x: downscaledOriginX,
                                                   y: downscaledOriginY,
                                                   width: downscaledWidth,
                                                   height: downscaledHeight)

                // Print the observation results to the console
                //print("Observation: \(observation)")
                //print("Downscaled Bounding Box: \(downscaledBoundingBox)")

                self.recognizedObjects = [RecognizedObject(label: rezObject.identifier, confidence: rezObject.confidence, boundingBox: downscaledBoundingBox)]
            } else {
                self.recognizedObjects = []
            }
        }
    }

    private func handlePillDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        
        DispatchQueue.main.async {
            var frameMiddlePoints: [[CGFloat]] = []
            
            self.pillObjects = results.compactMap { observation -> RecognizedObject? in
                guard let pillObject = observation.labels.first(where: { $0.identifier == "pill" }) else { return nil }
                
                let adjustedBoundingBoxHeight = observation.boundingBox.size.height * CGFloat(self.cameraAspectRatio)
                let adjustedBoundingBoxOriginY = (1 - observation.boundingBox.origin.y - observation.boundingBox.size.height) * CGFloat(self.cameraAspectRatio)
                
                let normalizedBoundingBox = CGRect(x: observation.boundingBox.origin.x,
                                                   y: adjustedBoundingBoxOriginY,
                                                   width: observation.boundingBox.size.width,
                                                   height: adjustedBoundingBoxHeight)
                
                // Calculate the middle point of the bounding box
                let middleX = normalizedBoundingBox.midX
                let middleY = normalizedBoundingBox.midY
                
                frameMiddlePoints.append([middleX, middleY])
                
                return RecognizedObject(label: pillObject.identifier, confidence: pillObject.confidence, boundingBox: normalizedBoundingBox)
            }
            
            // Store the middle points in the dictionary using the current frame number
            let currentFrame = self.pillMiddlePoints.count + 1
            self.pillMiddlePoints[currentFrame] = frameMiddlePoints
            self.onPillCoordsUpdate?(self.pillMiddlePoints)

            
            // Print the frame and pill middle points to the console
            print("Frame \(currentFrame): \(frameMiddlePoints)")
        }
    }

}


private var lastFrameTimestamp = Date()

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Calculate the time difference between the current and last frame
        let now = Date()
        let timeElapsed = now.timeIntervalSince(lastFrameTimestamp)
        lastFrameTimestamp = now
        
        // Calculate and print FPS
        let fps = 1.0 / timeElapsed
        print("FPS: \(fps)")
        
 
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let grayscalePixelBuffer = convertToGrayscale(pixelBuffer: pixelBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: grayscalePixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request, pillRequest].compactMap { $0 })
    }

}
