//
//  VisionObjectRecognitionViewController.swift
//  iOS_USCoinsDetector
//
//  Created by Roger Navarro on 12/3/20.
//

import UIKit
import AVFoundation
import Vision

class VisionObjectRecognitionViewController: ViewController {
    
    //MARK: - Properties
    private var detectionOverlay: CALayer! = nil
    
    // Vision parts
    private var requests = [VNRequest]()
    
    typealias Dollars = Decimal
    private let dollarLabels: [String:String] = [
        "penny":"1",
        "nickel":"5",
        "dime":"10",
        "quarter":"25",
        "dollar":"100"]
    private let coinColors: [String:[CGFloat]] = [
        "penny": [0.2, 1.0, 1.0, 0.4],
        "nickel": [0.2, 0.2, 1.0, 0.4],
        "dime": [1.0, 0.2, 1.0, 0.4],
        "quarter": [1.0, 0.2, 0.2, 0.4],
        "dollar": [0.2, 1.0, 0.3, 0.4]
    ]
    var baseAmount: Dollars = 0.0
    
    var currentTotal: Dollars = 0.0 {
        didSet {
            self.totalLabel.text = "\(self.baseAmount + self.currentTotal) $"
        }
    }
    
    var observationsSnapShot : [VNRecognizedObjectObservation] = []
    
    @discardableResult
    func setupVision() -> NSError? {
        // Setup Vision parts
        let error: NSError! = nil
        
        guard let modelURL = Bundle.main.url(forResource: "IOS coin Detector 1 Iteration 4720", withExtension: "mlmodelc") else {
            return NSError(domain: "VisionObjectRecognitionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing"])
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = self.getObservations(request.results) {
                        self.observationsSnapShot = results
                        self.calculateTotal(results)
                        self.drawVisionRequestResults(results)
                    } else {
                        self.observationsSnapShot = []
                        self.currentTotal = 0
                        self.detectionOverlay.sublayers = nil // remove all the old recognized objects
                    }
                })
            })
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
        
        return error
    }
    
    func getObservations(_ results: [Any]?) -> [VNRecognizedObjectObservation]?  {
        guard let results = results, !results.isEmpty else { return nil}
        var result: [VNRecognizedObjectObservation] = []
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            
            result.append(objectObservation)
        }
        
        return result.isEmpty ? nil : result
    }
    var bufferCount = 0
    //MARK: - IBActions
    
    @IBAction func addup(_ sender: Any) {
        self.baseAmount += currentTotal
        
        if observationsSnapShot.isEmpty { return }

        for observation in self.observationsSnapShot {
            CATransaction.begin()
            CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
            let box = VNImageRectForNormalizedRect(observation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            let balloon = CALayer()
            balloon.name = "plusSigns"
            balloon.contents = UIImage(named: "plus")!.cgImage
//
            balloon.bounds = box
            balloon.frame = CGRect(x: box.midY, y: box.midX, width: 50, height: 50)
            CATransaction.commit()
            self.rootLayer.insertSublayer(balloon, below: self.rootLayer)
            let flight = CAKeyframeAnimation(keyPath: "position")
            flight.duration = 0.3
            flight.values = [
                CGPoint(x: box.midY, y: box.midX),
                CGPoint(x: self.rootLayer.bounds.midX, y: 0.0)
            ].map { NSValue(cgPoint: $0) }
            
            flight.keyTimes = [0.0, 1.0]
            balloon.add(flight, forKey: nil)
            balloon.position = CGPoint(x: self.rootLayer.bounds.midX, y: -50.0)
        }
        

        
    }
    
    @IBAction func restartCount(_ sender: Any) {
        self.baseAmount = 0.0
    }
    //MARK: - Functions
    func calculateTotal(_ objectObservations: [VNRecognizedObjectObservation]) {
        if bufferCount != 5 {
            bufferCount+=1
            return
        }
        var total: Dollars = Dollars(0)
        for observation in objectObservations {
            switch observation.labels[0].identifier {
            case "penny":
                total += Dollars(0.01)
            case "nickel":
                total += Dollars(0.05)
            case "dime":
                total += Dollars(0.1)
            case "quarter":
                total += Dollars(0.25)
            case "dollar":
                total += Dollars(1.0)
            default:
                total += Dollars(0.0)
            }
        }
        self.currentTotal = total
        bufferCount = 0
    }
    
    func drawVisionRequestResults(_ objectObservations: [VNRecognizedObjectObservation]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        detectionOverlay.sublayers = nil // remove all the old recognized objects
        for objectObservation in objectObservations {
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds, identifier: topLabelObservation.identifier)
            
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                            identifier: topLabelObservation.identifier,
                                                            confidence: topLabelObservation.confidence)
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
        }
//        self.updateLayerGeometry()
        CATransaction.commit()
    }

    override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let exifOrientation = exifOrientationFromDeviceOrientation()
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: exifOrientation, options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    override func setupAVCapture() {
        super.setupAVCapture()
        
        // setup Vision parts
        setupLayers()
        updateLayerGeometry()
        setupVision()
        
        // start the capture
        startCaptureSession()
    }
    
    func setupLayers() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: bufferSize.width,
                                         height: bufferSize.height)
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
        
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let label = dollarLabels[identifier] ?? ""
        let formattedString = NSMutableAttributedString(string: label+"￠")
        let largeFont = UIFont(name: "Helvetica", size: 16.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: label.count + 1))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x:0, y: (-bounds.size.height/2) + 16, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect, identifier: String) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: coinColors[identifier] ?? [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = bounds.height/2

        return shapeLayer
    }
    
}
