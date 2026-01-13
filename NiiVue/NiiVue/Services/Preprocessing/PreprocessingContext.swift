import Foundation
import nnUNetPreprocessing

public struct PreprocessingContext: Codable, Sendable, Equatable {
    public struct Vector3D: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    public struct Matrix3x3D: Codable, Sendable, Equatable {
        public var c0: Vector3D
        public var c1: Vector3D
        public var c2: Vector3D

        public init(c0: Vector3D, c1: Vector3D, c2: Vector3D) {
            self.c0 = c0
            self.c1 = c1
            self.c2 = c2
        }

        public static var identity: Matrix3x3D {
            Matrix3x3D(
                c0: .init(x: 1, y: 0, z: 0),
                c1: .init(x: 0, y: 1, z: 0),
                c2: .init(x: 0, y: 0, z: 1)
            )
        }
    }

    public struct Shape3D: Codable, Sendable, Equatable {
        public var depth: Int
        public var height: Int
        public var width: Int

        public init(depth: Int, height: Int, width: Int) {
            self.depth = depth
            self.height = height
            self.width = width
        }
    }

    public struct Spacing3D: Codable, Sendable, Equatable {
        public var z: Double
        public var y: Double
        public var x: Double

        public init(z: Double, y: Double, x: Double) {
            self.z = z
            self.y = y
            self.x = x
        }
    }

    public var dicomOriginLPS: Vector3D
    public var dicomOrientationLPS: Matrix3x3D

    public var inputShape: Shape3D
    public var inputSpacing: Spacing3D

    public var transposeForward: [Int]
    public var transposeBackward: [Int]

    public var cropBoundingBox: BoundingBox?

    public var outputShape: Shape3D
    public var outputSpacing: Spacing3D

    public init(
        dicomOriginLPS: Vector3D,
        dicomOrientationLPS: Matrix3x3D,
        inputShape: Shape3D,
        inputSpacing: Spacing3D,
        transposeForward: [Int],
        transposeBackward: [Int],
        cropBoundingBox: BoundingBox?,
        outputShape: Shape3D,
        outputSpacing: Spacing3D
    ) {
        self.dicomOriginLPS = dicomOriginLPS
        self.dicomOrientationLPS = dicomOrientationLPS
        self.inputShape = inputShape
        self.inputSpacing = inputSpacing
        self.transposeForward = transposeForward
        self.transposeBackward = transposeBackward
        self.cropBoundingBox = cropBoundingBox
        self.outputShape = outputShape
        self.outputSpacing = outputSpacing
    }
}

