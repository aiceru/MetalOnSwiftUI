//
//  TextureView.swift
//  MetalOnSwiftUI
//
//  Created by Wooseok Son on 2021/10/08.
//

import Foundation
import SwiftUI
import MetalKit

struct TextureView: UIViewRepresentable {
    typealias UIViewType = MTKView
    var view: UIViewType!
    
    init() {
        view = MTKView(frame:.zero, device:MTLCreateSystemDefaultDevice())
    }
    
    func makeUIView(context: Context) -> UIViewType {
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator.renderer
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        
        let panRecognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan))
        let rotateRecognizer = UIRotationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleRotate))
        let pinchRecognizer = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch))
        view.addGestureRecognizer(panRecognizer)
        view.addGestureRecognizer(rotateRecognizer)
        view.addGestureRecognizer(pinchRecognizer)
        
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(view: view)
    }
    
    class Coordinator {
        var renderer: TextureRenderer!
        var view: MTKView
        var gestureTarget:Int = -1
        
        init(view: MTKView) {
            self.view = view
            renderer = TextureRenderer(device: view.device!)
        }
        
        func gestureLocation(gesture: UIGestureRecognizer) -> SIMD2<Float> {
            let b = gesture.view?.bounds
            let l = gesture.location(in: gesture.view)
            var location = SIMD2<Float>()
            location.x = Float(l.x) / Float(b!.width)
            location.y = Float(l.y) / Float(b!.height)
            return location
        }
        
        @objc func handlePan(gesture: UIPanGestureRecognizer) {
            let b = gesture.view?.bounds
            if gesture.state == UIPanGestureRecognizer.State.began {
                let location = gestureLocation(gesture: gesture)
                gestureTarget = renderer.findTargetImage(location:location)
            }
            if gestureTarget > -1 {
                let t = gesture.translation(in: gesture.view)
                
                var translation = SIMD2<Float>()
                translation.x = Float(t.x) / Float(b!.width)
                translation.y = Float(t.y) / Float(b!.height)
                
                renderer.moveCenter(target: gestureTarget, translation: translation)
                gesture.setTranslation(CGPoint.zero, in: gesture.view)
                view.setNeedsDisplay()
            }
        }
        
        @objc func handleRotate(gesture: UIRotationGestureRecognizer) {
            if gesture.state == UIPinchGestureRecognizer.State.began {
                let location = gestureLocation(gesture: gesture)
                gestureTarget = renderer.findTargetImage(location: location)
            }
            if gestureTarget > -1 {
                let r = gesture.rotation
                renderer.rotateRect(target: gestureTarget, radian: r)
                view.setNeedsDisplay()
            }
        }
        
        @objc func handlePinch(gesture: UIPinchGestureRecognizer) {
            if gesture.state == UIPinchGestureRecognizer.State.began {
                let location = gestureLocation(gesture: gesture)
                gestureTarget = renderer.findTargetImage(location: location)
            }
            if gestureTarget > -1 {
                let scale = gesture.scale
                
                renderer.resizeRect(target: gestureTarget, scale: scale)
                gesture.scale = 1.0
                view.setNeedsDisplay()
            }
        }
    }
}

class TextureRenderer: NSObject, MTKViewDelegate {
    var commandQueue: MTLCommandQueue!
    var renderPipelineState: MTLRenderPipelineState!
    
    var centerBuffer: MTLBuffer!
    var imageHalfSizeBuffer: MTLBuffer!
    var rotationBuffer: MTLBuffer!
    
    var textures: [MTLTexture] = []
    var scales: [Float] = [1.0, 1.0]
    
    var centers : [vector_float2] = [
        vector_float2(-100.0, -100.0),
         vector_float2(0.0, 0.0),
    ]
    var imageHalfSize: [vector_float2] = [
        vector_float2(0.0, 0.0),
        vector_float2(0.0, 0.0),
    ]
    var rotations : [Float] = [     // in radian
        0.0,
        0.0,
    ]
    
    var viewportSize: vector_uint2 = vector_uint2(0, 0)
    
    init(device: MTLDevice) {
        super.init()
        loadTexture(device: device)
        
        createRenderPipelineState(device: device)
        createCommandQueue(device: device)
    }
    
    func findTargetImage(location: SIMD2<Float>) -> Int {
        var beganPoint = SIMD2<Float>()
        beganPoint.x = location.x * Float(viewportSize.x) - Float(viewportSize.x) / 2.0
        beganPoint.y = location.y * Float(viewportSize.y) - Float(viewportSize.y) / 2.0
        
        for (i, center) in centers.enumerated() {
            if beganPoint.x >= center.x - imageHalfSize[i].x && beganPoint.x <= center.x + imageHalfSize[i].x &&
                beganPoint.y >= center.y - imageHalfSize[i].y && beganPoint.y <= center.y + imageHalfSize[i].y {
                return i
            }
        }
        return -1
    }
    
    func moveCenter(target: Int, translation: SIMD2<Float>) {
        var next = vector_float2()
        next.x = centers[target].x + (translation.x * Float(viewportSize.x))
        next.y = centers[target].y + (translation.y * Float(viewportSize.y))
        if next.x > Float(viewportSize.x)/2.0 - imageHalfSize[target].x ||
            next.x < imageHalfSize[target].x - Float(viewportSize.x)/2.0 {
            next.x = centers[target].x
        }
        if next.y > Float(viewportSize.y)/2.0 - imageHalfSize[target].y ||
            next.y < imageHalfSize[target].y - Float(viewportSize.y)/2.0 {
            next.y = centers[target].y
        }
        centers[target] = next
    }
    
    func resizeRect(target: Int, scale: CGFloat) {
        self.scales[target] *= Float(scale)
    }
    
    func rotateRect(target: Int, radian: CGFloat) {
        self.rotations[target] = Float(radian)
    }
    
    func loadTexture(device: MTLDevice) {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option : Any] = [.generateMipmaps : true, .SRGB : true]
        let lenna = try! loader.newTexture(name: "Lenna", scaleFactor: 1.0, bundle: nil, options: options)
        let hex = try! loader.newTexture(name: "hexpattern", scaleFactor: 1.0, bundle: nil, options: options)
        textures = [lenna, hex]
    }
    
    func createCommandQueue(device: MTLDevice) {
        commandQueue = device.makeCommandQueue()
    }
    
    func createRenderPipelineState(device: MTLDevice) {
        let library = device.makeDefaultLibrary()!
        let vertexProgram = library.makeFunction(name: "textureVertexShader")
        let fragmentProgram = library.makeFunction(name: "textureFragmentShader")
        
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgram
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        renderPipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    }
    
    func createBuffers(device: MTLDevice) {
        centerBuffer = device.makeBuffer(bytes: centers, length: centers.count * MemoryLayout.size(ofValue: centers[0]), options: [])
        imageHalfSizeBuffer = device.makeBuffer(bytes: imageHalfSize, length: imageHalfSize.count * MemoryLayout.size(ofValue: imageHalfSize[0]), options: [])
        rotationBuffer = device.makeBuffer(bytes: rotations, length: rotations.count * MemoryLayout.size(ofValue: rotations[0]), options: [])
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize.x = UInt32(size.width)
        viewportSize.y = UInt32(size.height)
    }
    
    func draw(in view: MTKView) {
        let screenSize = UIScreen.main.bounds
        for i in CountableRange(0...1) {
            imageHalfSize[i].x = Float(textures[i].width) / 2.0 * Float(screenSize.width) / Float(viewportSize.x) * scales[i]
            imageHalfSize[i].y = Float(textures[i].height) / 2.0 * Float(screenSize.height) / Float(viewportSize.y) * scales[i]
        }
        
        guard let drawable = view.currentDrawable else { return }
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 0)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setViewport(MTLViewport(originX: 0.0, originY: 0.0, width: Double(viewportSize[0]), height: Double(viewportSize[1]), znear: -1.0, zfar: 1.0))
        renderEncoder.setRenderPipelineState(renderPipelineState)
        
        createBuffers(device: view.device!)
        
        renderEncoder.setFragmentBuffer(centerBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentBuffer(imageHalfSizeBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(rotationBuffer, offset: 0, index: 2)
        renderEncoder.setFragmentBytes(&viewportSize, length: MemoryLayout.size(ofValue: viewportSize), index: 3)
        renderEncoder.setFragmentTextures(textures, range: CountableRange(0...1))
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
}
