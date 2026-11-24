import SwiftUI
import ARKit
import SceneKit
import simd

struct ARTraceViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARSessionViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.preferredFramesPerSecond = 60
        arView.automaticallyUpdatesLighting = false
        arView.rendersContinuously = false
        arView.antialiasingMode = .multisampling2X
        arView.backgroundColor = .black

        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.session.delegateQueue = .main
        arView.isAccessibilityElement = true
        arView.accessibilityLabel = "AR Camera Tracing Canvas"
        arView.accessibilityHint = "Double tap to place your reference image on a detected flat surface. When unlocked, drag with one finger to move, pinch to scale, and twist with two fingers to rotate."

        context.coordinator.attach(to: arView)
        viewModel.sceneController = context.coordinator

        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.viewModel = viewModel
        if viewModel.sceneController == nil {
            viewModel.sceneController = context.coordinator
        }
        context.coordinator.syncReticleVisibility(
            hasReference: viewModel.referenceImage != nil,
            isPlaced: viewModel.isPlaced
        )
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    // MARK: - Coordinator (ARSCNViewDelegate + ARSessionDelegate + Gestures)

    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate, UIGestureRecognizerDelegate, ARSceneControlling {
        weak var viewModel: ARSessionViewModel?
        private weak var arView: ARSCNView?

        private var placedAnchor: ARAnchor?
        private var manipulableNode: SCNNode?
        private var imagePlaneNode: SCNNode?
        private var reticleNode: SCNNode?

        private var currentCGImage: CGImage?
        private var currentAspectRatio: CGFloat = 1.0
        private var currentOpacity: Double = 0.55
        private var isAnchorLocked: Bool = false
        private var hasReference: Bool = false
        private var isSessionRunning: Bool = false

        private var uniformScale: Float = 1.0
        private var pinchStartScale: Float = 1.0
        private var lastRotationAngle: CGFloat = 0.0

        private var lastTelemetryTimestamp: TimeInterval = 0
        private var lastReticleUpdateTimestamp: TimeInterval = 0

        private let baseLongestEdgeMeters: CGFloat = 0.18
        private let minScaleFactor: Float = 0.20
        private let maxScaleFactor: Float = 4.50

        init(viewModel: ARSessionViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        @MainActor
        func attach(to view: ARSCNView) {
            self.arView = view
            setupReticleNode(in: view.scene)
            setupGestures(on: view)
        }

        @MainActor
        private func setupReticleNode(in scene: SCNScene) {
            let outerRing = SCNTorus(ringRadius: 0.045, pipeRadius: 0.0018)
            let ringMaterial = SCNMaterial()
            ringMaterial.lightingModel = .constant
            ringMaterial.diffuse.contents = UIColor.systemTeal.withAlphaComponent(0.90)
            ringMaterial.writesToDepthBuffer = false
            outerRing.materials = [ringMaterial]

            let centerDot = SCNCylinder(radius: 0.004, height: 0.0005)
            centerDot.materials = [ringMaterial]

            let node = SCNNode()
            node.addChildNode(SCNNode(geometry: outerRing))
            node.addChildNode(SCNNode(geometry: centerDot))
            node.isHidden = true
            scene.rootNode.addChildNode(node)
            self.reticleNode = node
        }

        @MainActor
        private func setupGestures(on view: ARSCNView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
            rotation.delegate = self
            view.addGestureRecognizer(rotation)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            let isPinchOrRotateA = gestureRecognizer is UIPinchGestureRecognizer || gestureRecognizer is UIRotationGestureRecognizer
            let isPinchOrRotateB = otherGestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIRotationGestureRecognizer
            return isPinchOrRotateA && isPinchOrRotateB
        }

        // MARK: - ARSceneControlling

        @MainActor
        func resumeSession(planeDetectionEnabled: Bool) {
            guard ARWorldTrackingConfiguration.isSupported, let arView else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = planeDetectionEnabled ? [.horizontal] : []
            config.isLightEstimationEnabled = true
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation) {
                // Keep frame semantics empty so A14 GPU stays cool at a steady 60 fps.
                config.frameSemantics = []
            }
            arView.session.run(config, options: [])
            isSessionRunning = true
        }

        @MainActor
        func restartPlaneDetection(resetTracking: Bool) {
            guard ARWorldTrackingConfiguration.isSupported, let arView else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.isLightEstimationEnabled = true
            let options: ARSession.RunOptions = resetTracking ? [.resetTracking, .removeExistingAnchors] : []
            arView.session.run(config, options: options)
            isSessionRunning = true
        }

        @MainActor
        func pauseSession() {
            guard isSessionRunning, let arView else { return }
            arView.session.pause()
            isSessionRunning = false
        }

        @MainActor
        func placeReferenceAtScreenCenter() -> Bool {
            guard let arView else { return false }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            return placeAnchorUsingRaycast(at: center, in: arView)
        }

        @MainActor
        func placeReferenceAtFallbackDistance() -> Bool {
            guard let arView, let frame = arView.session.currentFrame else { return false }
            let camTransform = frame.camera.transform

            // Project 25 cm along the camera optical axis (-Z), then align upright on a horizontal plane.
            let camOrigin = SIMD3<Float>(camTransform.columns.3.x, camTransform.columns.3.y, camTransform.columns.3.z)
            let camForward = -SIMD3<Float>(camTransform.columns.2.x, camTransform.columns.2.y, camTransform.columns.2.z)
            let targetPos = camOrigin + camForward * 0.25

            let alignedTransform = Self.makeScreenAlignedHorizontalTransform(
                position: targetPos,
                cameraTransform: camTransform
            )
            installAnchor(transform: alignedTransform, in: arView)
            return true
        }

        @MainActor
        func removePlacedAnchor() {
            if let existing = placedAnchor, let arView {
                arView.session.remove(anchor: existing)
            }
            placedAnchor = nil
            manipulableNode?.removeFromParentNode()
            manipulableNode = nil
            imagePlaneNode = nil
            uniformScale = 1.0
            isAnchorLocked = false
        }

        @MainActor
        func updateOverlayTexture(_ cgImage: CGImage?, aspectRatio: CGFloat) {
            self.currentCGImage = cgImage
            self.currentAspectRatio = max(0.1, aspectRatio)
            self.hasReference = (cgImage != nil)

            guard let planeNode = imagePlaneNode,
                  let plane = planeNode.geometry as? SCNPlane else { return }

            let size = computePlaneDimensions(aspectRatio: currentAspectRatio)
            plane.width = size.width
            plane.height = size.height
            plane.firstMaterial?.diffuse.contents = cgImage
        }

        @MainActor
        func updateOverlayOpacity(_ opacity: Double) {
            self.currentOpacity = opacity
            imagePlaneNode?.opacity = CGFloat(opacity)
        }

        @MainActor
        func setAnchorLocked(_ isLocked: Bool) {
            self.isAnchorLocked = isLocked
            resumeSession(planeDetectionEnabled: !isLocked)
            if isLocked {
                reticleNode?.isHidden = true
            }
        }

        @MainActor
        func nudgeScale(by factor: Float) {
            guard !isAnchorLocked, let node = manipulableNode else { return }
            uniformScale = min(max(uniformScale * factor, minScaleFactor), maxScaleFactor)
            node.simdScale = SIMD3<Float>(repeating: uniformScale)
            viewModel?.didUpdateScale(uniformScale)
        }

        @MainActor
        func nudgeRotation(by radians: Float) {
            guard !isAnchorLocked, let node = manipulableNode else { return }
            node.eulerAngles.y += radians
        }

        @MainActor
        func resetManipulableTransform() {
            guard !isAnchorLocked, let node = manipulableNode else { return }
            uniformScale = 1.0
            node.simdPosition = SIMD3<Float>(0, 0.001, 0)
            node.eulerAngles = SCNVector3Zero
            node.simdScale = SIMD3<Float>(repeating: 1.0)
        }

        @MainActor
        func captureSnapshot() -> UIImage? {
            guard let arView else { return nil }
            let wasReticleHidden = reticleNode?.isHidden ?? true
            reticleNode?.isHidden = true
            let image = arView.snapshot()
            reticleNode?.isHidden = wasReticleHidden
            return image
        }

        @MainActor
        func syncReticleVisibility(hasReference: Bool, isPlaced: Bool) {
            self.hasReference = hasReference
            if !hasReference || isPlaced || isAnchorLocked {
                reticleNode?.isHidden = true
            }
        }

        // MARK: - Raycast & Anchor Construction

        @MainActor
        private func placeAnchorUsingRaycast(at screenPoint: CGPoint, in arView: ARSCNView) -> Bool {
            let hitResult: ARRaycastResult? = {
                if let geometryQuery = arView.raycastQuery(
                    from: screenPoint,
                    allowing: .existingPlaneGeometry,
                    alignment: .horizontal
                ), let first = arView.session.raycast(geometryQuery).first {
                    return first
                }
                if let infiniteQuery = arView.raycastQuery(
                    from: screenPoint,
                    allowing: .existingPlaneInfinite,
                    alignment: .horizontal
                ), let first = arView.session.raycast(infiniteQuery).first {
                    return first
                }
                if let estimatedQuery = arView.raycastQuery(
                    from: screenPoint,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                ), let first = arView.session.raycast(estimatedQuery).first {
                    return first
                }
                return nil
            }()

            guard let hit = hitResult else { return false }
            let hitPosition = SIMD3<Float>(
                hit.worldTransform.columns.3.x,
                hit.worldTransform.columns.3.y,
                hit.worldTransform.columns.3.z
            )
            let cameraTransform = arView.session.currentFrame?.camera.transform ?? matrix_identity_float4x4
            let alignedTransform = Self.makeScreenAlignedHorizontalTransform(
                position: hitPosition,
                cameraTransform: cameraTransform
            )
            installAnchor(transform: alignedTransform, in: arView)
            return true
        }

        @MainActor
        private func installAnchor(transform: simd_float4x4, in arView: ARSCNView) {
            if let existing = placedAnchor {
                arView.session.remove(anchor: existing)
            }
            let anchor = ARAnchor(name: "TraceARReferenceAnchor", transform: transform)
            placedAnchor = anchor
            uniformScale = 1.0
            reticleNode?.isHidden = true
            arView.session.add(anchor: anchor)
        }

        /// Aligns the horizontal anchor to the iPhone's screen-right (+X) axis so portrait stand placement never gimbal-locks when looking straight down.
        static func makeScreenAlignedHorizontalTransform(
            position: SIMD3<Float>,
            cameraTransform: simd_float4x4
        ) -> simd_float4x4 {
            let camRight = SIMD3<Float>(
                cameraTransform.columns.0.x,
                0,
                cameraTransform.columns.0.z
            )
            let lengthSq = simd_length_squared(camRight)
            let xAxis: SIMD3<Float> = lengthSq > 0.0001
                ? simd_normalize(camRight)
                : SIMD3<Float>(1, 0, 0)
            let yAxis = SIMD3<Float>(0, 1, 0)
            let zAxis = simd_normalize(simd_cross(xAxis, yAxis))

            return simd_float4x4(
                SIMD4<Float>(xAxis.x, xAxis.y, xAxis.z, 0),
                SIMD4<Float>(yAxis.x, yAxis.y, yAxis.z, 0),
                SIMD4<Float>(zAxis.x, zAxis.y, zAxis.z, 0),
                SIMD4<Float>(position.x, position.y, position.z, 1)
            )
        }

        private func computePlaneDimensions(aspectRatio: CGFloat) -> CGSize {
            if aspectRatio >= 1.0 {
                return CGSize(
                    width: baseLongestEdgeMeters,
                    height: baseLongestEdgeMeters / aspectRatio
                )
            } else {
                return CGSize(
                    width: baseLongestEdgeMeters * aspectRatio,
                    height: baseLongestEdgeMeters
                )
            }
        }

        // MARK: - Gesture Handlers

        @MainActor
        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended,
                  let arView,
                  hasReference,
                  placedAnchor == nil else { return }

            let location = gesture.location(in: arView)
            if placeAnchorUsingRaycast(at: location, in: arView) {
                Task { @MainActor [weak self] in
                    self?.viewModel?.notifyPlacedViaTap()
                }
            }
        }

        @MainActor
        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard !isAnchorLocked,
                  let arView,
                  let manipulable = manipulableNode,
                  let parentAnchorNode = manipulable.parent else { return }

            guard gesture.state == .changed else { return }
            let location = gesture.location(in: arView)

            guard let query = arView.raycastQuery(
                from: location,
                allowing: .existingPlaneInfinite,
                alignment: .horizontal
            ), let hit = arView.session.raycast(query).first else {
                return
            }

            let worldPos = SCNVector3(
                hit.worldTransform.columns.3.x,
                hit.worldTransform.columns.3.y + 0.001,
                hit.worldTransform.columns.3.z
            )
            let localPos = parentAnchorNode.convertPosition(worldPos, from: nil)
            manipulable.position = SCNVector3(localPos.x, 0.001, localPos.z)
        }

        @MainActor
        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard !isAnchorLocked, let manipulable = manipulableNode else { return }

            switch gesture.state {
            case .began:
                pinchStartScale = uniformScale
            case .changed:
                let proposed = pinchStartScale * Float(gesture.scale)
                uniformScale = min(max(proposed, minScaleFactor), maxScaleFactor)
                manipulable.simdScale = SIMD3<Float>(repeating: uniformScale)
                let reportedScale = uniformScale
                Task { @MainActor [weak self] in
                    self?.viewModel?.didUpdateScale(reportedScale)
                }
            default:
                break
            }
        }

        @MainActor
        @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard !isAnchorLocked, let manipulable = manipulableNode else { return }

            switch gesture.state {
            case .began:
                lastRotationAngle = gesture.rotation
            case .changed:
                let delta = gesture.rotation - lastRotationAngle
                lastRotationAngle = gesture.rotation
                // Negate so clockwise finger twist rotates the flat paper image clockwise on screen.
                manipulable.eulerAngles.y -= Float(delta)
            default:
                break
            }
        }

        // MARK: - ARSCNViewDelegate

        func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            if anchor is ARPlaneAnchor {
                Task { @MainActor [weak self] in
                    self?.viewModel?.markPlaneDetected()
                }
                return
            }

            guard anchor.identifier == placedAnchor?.identifier else { return }

            let container = SCNNode()
            container.simdPosition = SIMD3<Float>(0, 0.001, 0)
            container.simdScale = SIMD3<Float>(repeating: uniformScale)

            let size = computePlaneDimensions(aspectRatio: currentAspectRatio)
            let plane = SCNPlane(width: size.width, height: size.height)

            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = currentCGImage
            material.isDoubleSided = true
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            plane.materials = [material]

            let planeHolder = SCNNode(geometry: plane)
            planeHolder.eulerAngles.x = -.pi / 2
            planeHolder.opacity = CGFloat(currentOpacity)
            planeHolder.renderingOrder = 100

            container.addChildNode(planeHolder)
            node.addChildNode(container)

            self.manipulableNode = container
            self.imagePlaneNode = planeHolder
        }

        // MARK: - ARSessionDelegate (Throttled to keep 60 fps lockstep)

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let now = frame.timestamp
            let shouldUpdateReticle = hasReference && placedAnchor == nil && !isAnchorLocked && (now - lastReticleUpdateTimestamp >= 0.08)
            if shouldUpdateReticle {
                lastReticleUpdateTimestamp = now
            }

            let shouldSendTelemetry = (now - lastTelemetryTimestamp >= 0.25)
            if shouldSendTelemetry {
                lastTelemetryTimestamp = now
            }

            guard shouldUpdateReticle || shouldSendTelemetry else { return }

            let quality = Self.mapTrackingState(frame.camera.trackingState)
            let ambientLumens = frame.lightEstimate?.ambientIntensity

            Task { @MainActor [weak self] in
                guard let self else { return }
                if shouldUpdateReticle {
                    self.updateReticlePosition()
                }
                if shouldSendTelemetry {
                    let reticleVisible = !(self.reticleNode?.isHidden ?? true)
                    self.viewModel?.receiveFrameTelemetry(
                        quality: quality,
                        ambientLumens: ambientLumens,
                        reticleHitsPlane: reticleVisible
                    )
                }
            }
        }

        @MainActor
        private func updateReticlePosition() {
            guard let arView, let reticle = reticleNode else { return }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)

            let hit: ARRaycastResult? = {
                if let q = arView.raycastQuery(from: center, allowing: .existingPlaneGeometry, alignment: .horizontal),
                   let first = arView.session.raycast(q).first {
                    return first
                }
                if let q = arView.raycastQuery(from: center, allowing: .existingPlaneInfinite, alignment: .horizontal),
                   let first = arView.session.raycast(q).first {
                    return first
                }
                return nil
            }()

            if let hit {
                reticle.simdWorldTransform = hit.worldTransform
                reticle.isHidden = false
            } else {
                reticle.isHidden = true
            }
        }

        static func mapTrackingState(_ state: ARCamera.TrackingState) -> TrackingQuality {
            switch state {
            case .notAvailable:
                return .notAvailable
            case .normal:
                return .normal
            case .limited(let reason):
                switch reason {
                case .initializing:
                    return .initializing
                case .excessiveMotion:
                    return .limitedExcessiveMotion
                case .insufficientFeatures:
                    return .limitedInsufficientFeatures
                case .relocalizing:
                    return .limitedRelocalizing
                @unknown default:
                    return .initializing
                }
            }
        }
    }
}
