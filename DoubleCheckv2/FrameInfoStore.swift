import SwiftUI
import Combine

class FrameInfoStore: ObservableObject {
    @Published private(set) var frameData: [[String: Any]] = []
    private(set) var currentFrame: Int = 0
    var onPillCoordsUpdate: ((_ pillCoords: [Int: [[CGFloat]]]) -> Void)?

    func updateCurrentFrame(_ newData: [String: Any]) {
        if currentFrame < frameData.count {
            frameData[currentFrame] = newData
        } else {
            frameData.append(newData)
        }
    }

    func nextFrame() {
        currentFrame += 1
    }

    func previousFrame() {
        if currentFrame > 0 {
            currentFrame -= 1
        }
    }
    
    func updatePillCoords(pillCoords: [Int: [[CGFloat]]]) {
        frameData[currentFrame]["pill_coords"] = pillCoords
    }


    func getCurrentFrameData() -> [String: Any] {
        guard currentFrame < frameData.count else {
            return [:]
        }
        return frameData[currentFrame]
    }

}
