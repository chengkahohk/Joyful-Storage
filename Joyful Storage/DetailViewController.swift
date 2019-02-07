//
//  DetailViewController.swift
//  Picogram
//
//  Created by Bear Cahill on 10/5/18.
//  Copyright © 2018 Brainwash Inc. All rights reserved.
//

import UIKit

class DetailViewController: UIViewController {


    @IBOutlet weak var ivImage: UIImageView!
    @IBOutlet weak var scrollView: UIScrollView!
    
    var detailItem: PicogramItem?
    
    func configureView() {
        if let detail = detailItem {
        
            ivImage.image = detail.image
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        
        configureView()
    }
    fileprivate func updateMinZoomScaleForSize(_ size: CGSize) {
        let widthScale = size.width / ivImage.bounds.width
        let heightScale = size.height / ivImage.bounds.height
        let minScale = min(widthScale, heightScale)
        
        scrollView.minimumZoomScale = minScale
        scrollView.zoomScale = minScale
        scrollView.maximumZoomScale = 6.0
    }
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateMinZoomScaleForSize(view.bounds.size)
    }

}

extension DetailViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return ivImage
    }
}

