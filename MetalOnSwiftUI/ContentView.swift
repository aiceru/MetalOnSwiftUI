//
//  ContentView.swift
//  MetalOnSwiftUI
//
//  Created by Wooseok Son on 2021/10/06.
//

import SwiftUI
import MetalKit

struct ContentView: View {
    var body: some View {
        TextureView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct MetalView: UIViewRepresentable {
    var colorData: [Float]
    init() {
        colorData =
        [1, 0, 0, 1,
         0, 1, 0, 1,
         0, 0, 1, 1,
        0, 0, 1, 1]
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: UIViewRepresentableContext<MetalView>) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = true
        mtkView.framebufferOnly = true
        mtkView.drawableSize = mtkView.frame.size
        
        let dragRecognizer = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDrag))
        mtkView.addGestureRecognizer(dragRecognizer)
        
        context.coordinator.setView(view: mtkView)
        
        return mtkView
    }
    
    
    func updateUIView(_ uiView: MTKView, context: Context) {
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalView
        var device: MTLDevice!
        var commandQueue: MTLCommandQueue!
        var pipelineState: MTLRenderPipelineState!
        var posData: [Float]
        var colorData: [Float]
        var timer: CADisplayLink!
        var mtkView: MTKView!
        
        init(_ parent: MetalView) {
            self.parent = parent
            device = MTLCreateSystemDefaultDevice()
            colorData = parent.colorData
            let screenSize = UIScreen.main.bounds
            posData = [Float(screenSize.width)/2, Float(screenSize.height)/2]
            
            let defaultLibrary = device.makeDefaultLibrary()!
            let fragmentProgram = defaultLibrary.makeFunction(name: "basic_fragment")
            let vertexProgram = defaultLibrary.makeFunction(name: "basic_vertex")
            
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
            commandQueue = device.makeCommandQueue()
            
            super.init()
        }
        
        func setView(view: MTKView) {
            self.mtkView = view
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        }
        
        func draw(in view: MTKView) {
            render()
        }
        
        func render() {
            guard let drawable = self.mtkView.currentDrawable else { return }
            
            let frameSize = [Float(mtkView.frame.width), Float(mtkView.frame.height)]
            
            let posSize = posData.count * MemoryLayout.size(ofValue: posData[0])
            let posBuffer = device.makeBuffer(bytes: posData, length: posSize, options: [])
            let colorSize = colorData.count * MemoryLayout.size(ofValue: colorData[0])
            let colorBuffer = device.makeBuffer(bytes: colorData, length: colorSize, options: [])
            let sSizeLen = frameSize.count * MemoryLayout.size(ofValue: frameSize[0])
            let sSizeBuffer = device.makeBuffer(bytes: frameSize, length: sSizeLen, options: [])
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
            
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(sSizeBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(posBuffer, offset: 0, index: 1)
            renderEncoder.setVertexBuffer(colorBuffer, offset: 0, index: 2)
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        
        @objc func handleDrag(gesture: UIPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let x = Float(location.x)
            let y = Float(location.y)
            if x <= posData[0]+20 && x >= posData[0]-20 && y <= posData[1]+20 && y >= posData[1]-20 {
                posData[0] = Float(location.x)
                posData[1] = Float(location.y)
                mtkView.setNeedsDisplay()
            }
        }
    }
}

