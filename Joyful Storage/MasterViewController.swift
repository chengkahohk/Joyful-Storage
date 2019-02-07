//
//  MasterViewController.swift
//  Picogram
//
//  Created by Bear Cahill on 10/5/18.
//  Copyright © 2018 Brainwash Inc. All rights reserved.
//

import UIKit
import AWSMobileClient
import AWSAppSync
import AWSS3

// *** In case someone is looking for resizing image to less than 1MB
extension UIImage {
    

    func resize(withPercentage percentage: CGFloat) -> UIImage? {
        var newRect = CGRect(origin: .zero, size: CGSize(width: size.width*percentage, height: size.height*percentage))
        UIGraphicsBeginImageContextWithOptions(newRect.size, true, 1)
        self.draw(in: newRect)
        defer {UIGraphicsEndImageContext()}
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    func resizeTo(MB: Double) -> UIImage? {
        guard let fileSize = self.pngData()?.count else {return nil}
        let fileSizeInMB = CGFloat(fileSize)/(1024.0*1024.0)//form bytes to MB
        let percentage = 1/fileSizeInMB
        return resize(withPercentage: percentage)
    }
    func resizeWithWidth(width: CGFloat) -> UIImage? {
        let imageView = UIImageView(frame: CGRect(origin: .zero, size: CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))))
        imageView.contentMode = .scaleAspectFit
        imageView.image = self
        UIGraphicsBeginImageContextWithOptions(imageView.bounds.size, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        imageView.layer.render(in: context)
        guard let result = UIGraphicsGetImageFromCurrentImageContext() else { return nil }
        UIGraphicsEndImageContext()
        return result
    }
}

@objcMembers
class PicogramItem {
    var id = UUID().uuidString
    var userName = AWSMobileClient.sharedInstance().username!
    var imageName = "\(String(describing: AWSMobileClient.sharedInstance().username!))\(Date().timeIntervalSince1970)"
    var image : UIImage?
}
@objcMembers
class PicoCell : UITableViewCell {
    @IBOutlet weak var ivImage: UIImageView!
    @IBOutlet weak var lblUser: UILabel!
    
    static var df : DateFormatter?
    
    func configCell(item : PicogramItem) {
        if PicoCell.df == nil {
            PicoCell.df = DateFormatter()
            PicoCell.df?.dateStyle = .medium
            PicoCell.df?.timeStyle = .medium
        }
        
        self.ivImage.image = item.image
        self.lblUser.text = item.userName
    }
}
@objcMembers
class MasterViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    var detailViewController: DetailViewController? = nil
    var objects = [PicogramItem]()
    
    let imgPicker = UIImagePickerController()
    var newItem : PicogramItem?
    var appSyncClient : AWSAppSyncClient?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        navigationItem.leftBarButtonItem = editButtonItem
        
        let addButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(promptForPic))
        navigationItem.rightBarButtonItem = addButton
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? DetailViewController
        }
        
        imgPicker.delegate = self
        appSyncClient = (UIApplication.shared.delegate as! AppDelegate).appSyncClient
        
        
        checkSignIn()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        clearsSelectionOnViewWillAppear = splitViewController!.isCollapsed
        super.viewWillAppear(animated)
    }
    
    func checkSignIn() {
        if AWSMobileClient.sharedInstance().isSignedIn {
            fetchItems { (success) in
                if success {
                    DispatchQueue.main.async {
                        self.tableView.reloadData()
                    }
                }
            }
        }
        else {
            AWSMobileClient.sharedInstance().showSignIn(navigationController: self.navigationController!) { (userState, error) in
                guard error == nil else { return }
                guard userState != nil else { return }
                if userState == .signedIn {
                    print ("success!")
                    print (AWSMobileClient.sharedInstance().username ?? "no username")
                    self.fetchItems { (success) in
                        if success {
                            DispatchQueue.main.async {
                                self.tableView.reloadData()
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Segues
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail" {
            if let indexPath = tableView.indexPathForSelectedRow {
                let object = objects[indexPath.row]
                let controller = (segue.destination as! UINavigationController).topViewController as! DetailViewController
                controller.detailItem = object
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
    }
    
    // MARK: - Table View
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return objects.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cellPico", for: indexPath) as! PicoCell
        
        let item = objects[indexPath.row]
        cell.configCell(item: item)
        if item.image == nil {
            downloadData(name: item.imageName, forItemAtIndex: indexPath.row)
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let item = objects[indexPath.row]
            objects.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            deleteOnline(item: item) { (success) in
                print (success)
                if success == true {
                    self.deleteFile(name: item.imageName)
                }
            }
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view.
        }
    }
    
    // MARK: - Image Picker
    
    @objc
    func promptForPic() {
        let ac = UIAlertController.init(title: "Source",
                                        message: "Where do you want to get your image?",
                                        preferredStyle: .actionSheet)
        
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            ac.addAction(UIAlertAction.init(title: "Camera",
                                            style: .default, handler: { (aa) in
                                                self.picFromCamera()
            }))
        }
        else {
            picFromLibrary() // bypass prompt
            return
        }
        
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            ac.addAction(UIAlertAction.init(title: "Photo Library",
                                            style: .default, handler: { (aa) in
                                                self.picFromLibrary()
            }))
        }
        
        self.present(ac, animated: true, completion: nil)
    }
    
    func picFromLibrary() {
        imgPicker.allowsEditing = true
        imgPicker.sourceType = .photoLibrary
        imgPicker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary)!
        imgPicker.modalPresentationStyle = .popover
        present(imgPicker, animated: true, completion: nil)
    }
    
    func picFromCamera() {
        imgPicker.allowsEditing = true
        imgPicker.sourceType = UIImagePickerController.SourceType.camera
        imgPicker.cameraCaptureMode = .photo
        imgPicker.modalPresentationStyle = .fullScreen
        present(imgPicker,animated: true,completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        dismiss(animated:true, completion: nil)
        if let newImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage
            ?? info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
            insertNewObject(img: newImage)
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    func insertNewObject(img : UIImage) {
        newItem = PicogramItem()
        newItem!.image = img
        objects.insert(newItem!, at: 0)
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.insertRows(at: [indexPath], with: .automatic)
        
        storeOnline(item: newItem!) { (success) in
            self.uploadImage(name: self.newItem!.imageName, img: self.newItem!.image!, completion: { (success) in
                print (success)
            })
        }
    }
    
    func storeOnline(item: PicogramItem, completion: @escaping (Bool)->Void) {
        let input = CreatePicoInput(id: item.id, userName: item.userName , imageName: item.imageName )
        let mut = CreatePicoMutation(input: input)
        appSyncClient?.perform(mutation: mut) { (result, error) in
            completion(error == nil)
        }
    }
    
    func deleteOnline(item: PicogramItem, completion: @escaping (Bool)->Void) {
        let input = DeletePicoInput(id: item.id)
        let mut = DeletePicoMutation(input: input)
        appSyncClient?.perform(mutation: mut) { (result, error) in
            completion(error == nil)
        }
    }
    
    func fetchItems(completion: @escaping (Bool)->Void) {
        let q = ListPicosQuery()
        let msfi = ModelStringFilterInput(eq: AWSMobileClient.sharedInstance().username!)
        let mpifi = ModelPicoFilterInput(userName: msfi)
        q.filter = mpifi
        appSyncClient?.fetch(query: q, cachePolicy: .fetchIgnoringCacheData) { (result, error) in
            guard error == nil else { completion(false); return }
            guard let pfs = result?.data?.listPicos?.items else { completion(false); return }
            self.objects.removeAll()
            pfs.forEach({ (item) in
                let newPost = PicogramItem()
                newPost.id = item?.id ?? ""
                newPost.imageName = item?.imageName ?? ""
                newPost.userName = item?.userName ?? ""
                self.objects.append(newPost)
            })
            completion(true)
        }
    }
    
    func uploadImage(name: String, img: UIImage, completion: @escaping (Bool)->Void) {
      let img = img.resizeWithWidth(width: 700) // Force change image size
        guard let data = img!.pngData() else { completion(false); return }
        
        let exp = AWSS3TransferUtilityUploadExpression()
        exp.progressBlock = {(task, progress) in
            print (progress.fractionCompleted)
        }
  
        
        let tUtil = AWSS3TransferUtility.default()

        tUtil.uploadData(data, key: "public/\(name).png", contentType: "image/png", expression: exp) { (task, error) in
            completion(error == nil)
        }
    }
    
    func downloadData(name: String, forItemAtIndex index : Int) {
        guard name.count > 0 else { return }
        
        let tUtil = AWSS3TransferUtility.default()
        tUtil.downloadData(forKey: "public/\(name).png", expression: nil) { (task, URL, data, error) in
            guard let d = data, d.count > 500 else { return }
            guard index < self.objects.count else { return }
            let item = self.objects[index]
            item.image = UIImage(data: d)
            DispatchQueue.main.async {
                self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
            }
        }
    }
    
    func deleteFile(name: String) {
        let credProv = AWSCognitoCredentialsProvider(regionType: .USEast1, identityPoolId: "us-east-1:65d797be-22c0-4371-af89-703eb97de2e9")
        let conf = AWSServiceConfiguration(region: .USEast1, credentialsProvider: credProv)
        AWSServiceManager.default()?.defaultServiceConfiguration = conf
        
        let s3 = AWSS3.default()
        guard let dor = AWSS3DeleteObjectRequest() else {
            return
        }
        dor.bucket = "picofilestorageforimages"
        dor.key = "public/\(name).png"
        s3.deleteObject(dor) { (output, error) in
            print ("\(String(describing: error?.localizedDescription))")
            print ("\(String(describing: output))")
        }
    }
    
}

