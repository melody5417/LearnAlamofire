//
//  PhotoBrowserCollectionViewController.swift
//  Photomania
//
//  Created by Essan Parto on 2014-08-20.
//  Copyright (c) 2014 Essan Parto. All rights reserved.
//

import UIKit
import Alamofire

class PhotoBrowserCollectionViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
  
  var photos = Set<PhotoInfo>()
  
  private let refreshControl = UIRefreshControl()
  
  // 当前是否在更新照片
  private var populatingPhotos = false
  // 正在浏览的是哪个照片页面
  private var currentPage = 1
  
  private let PhotoBrowserCellIdentifier = "PhotoBrowserCell"
  private let PhotoBrowserFooterViewIdentifier = "PhotoBrowserFooterView"
  
  // MARK: Life-cycle
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    setupView()
    
    populatePhotos()
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }
  
  // MARK: CollectionView
  
  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return photos.count
  }
  
  override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoBrowserCellIdentifier, for: indexPath) as? PhotoBrowserCollectionViewCell else { return UICollectionViewCell() }
    
    // 为 photos 集合中的对象创建了另外的 Alamofire 请求
    let photoInfo = photos[photos.index(photos.startIndex, offsetBy: indexPath.item)]
    Alamofire.request(photoInfo.url, method: .get).response {
      dataResponse in
      guard let data = dataResponse.data else { return }
      let image = UIImage(data: data)
      cell.imageView.image = image
    }
    
    return cell
  }
  
  override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
    return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: PhotoBrowserFooterViewIdentifier, for: indexPath)
  }
  
  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    performSegue(withIdentifier: "ShowPhoto", sender: photos[photos.index(photos.startIndex, offsetBy: indexPath.item)].id)
  }
  
  // MARK: Helper
  
  private func setupView() {
    navigationController?.setNavigationBarHidden(false, animated: true)
    
    guard let collectionView = collectionView else { return }
    let layout = UICollectionViewFlowLayout()
    let itemWidth = (view.bounds.width - 2) / 3
    layout.itemSize = CGSize(width: itemWidth, height: itemWidth)
    layout.minimumInteritemSpacing = 1
    layout.minimumLineSpacing = 1
    layout.footerReferenceSize = CGSize(width: collectionView.bounds.width, height: 100)
    
    collectionView.collectionViewLayout = layout
    
    let titleLabel = UILabel(frame: CGRect(x: 0.0, y: 0.0, width: 60.0, height: 30.0))
    titleLabel.text = "Photomania"
    titleLabel.textColor = .white
    titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
    navigationItem.titleView = titleLabel
    
    collectionView.register(PhotoBrowserCollectionViewCell.classForCoder(), forCellWithReuseIdentifier: PhotoBrowserCellIdentifier)
    collectionView.register(PhotoBrowserCollectionViewLoadingCell.classForCoder(), forSupplementaryViewOfKind: UICollectionElementKindSectionFooter, withReuseIdentifier: PhotoBrowserFooterViewIdentifier)
    
    refreshControl.tintColor = .white
    refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
    collectionView.addSubview(refreshControl)
  }
  
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if let destination = segue.destination as? PhotoViewerViewController, let id = sender as? Int, segue.identifier == "ShowPhoto" {
      destination.photoID = id
      destination.hidesBottomBarWhenPushed = true
    }
  }
  
  // 1. 一旦您滚动超过了 80% 的页面，那么 scrollViewDidScroll() 方法将会加载更多的图片。
  override func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if scrollView.contentOffset.y + view.frame.height > scrollView.contentSize.height * 0.8 {
      populatePhotos()
    }
  }
  
  private func populatePhotos() {
    // 2  populatePhotos() 方法在 currentPage 当中加载图片，并且使用 populatingPhotos 作为标记，以防止还在加载当前界面时加载下一个页面。
    if populatingPhotos { return }
    
    populatingPhotos = true
    
    // 3 使用了我们创建的路由。只需将页数传递进去，它将为该页面构造 URL 字符串。500px.com 网站在每次 API 调用后返回大约50张图片，因此您需要为下一批照片的显示再次调用路由。
    Alamofire.request(Five100px.Router.popularPhotos(currentPage)).responseJSON {
      response in
      
      guard let JSON = response.result.value, response.result.error == nil else {
        self.populatingPhotos = false
        return
      }
      
      // 4 要注意，.responseJSON() 后面的代码块：completion handler(完成处理方法)必须在主线程运行。如果您正在执行其他的长期运行操作，比如说调用 API，那么您必须使用 GCD 来将您的代码调度到另一个队列运行。在本示例中，我们使用QoSClass.userInitiated来运行这个操作，这就是以前的 DISPATCH_QUEUE_PRIORITY_HIGH。
      DispatchQueue.global(qos: .userInitiated).async {
        // 5 您可能会关心 JSON 数据中的 photos 关键字，其位于数组中的字典中。每个字典都包含有一张图片的信息。
        guard let photoJsons = (JSON as AnyObject).value(forKey: "photos") as? [[String: Any]] else { return }
        
        // 6 接下来我们会在添加新的数据前存储图片的当前数量，使用它来更新 collectionView
        let lastItemCount = self.photos.count
        
        // 7 forEach 函数将遍历获取到的 photoJsons 字典数组，筛除掉 nsfw(Not Safe For Work) 图片，然后将 PhotoInfo 对象插入到 photos 集合当中。这个结构体是在 Five100px.swift 当中定义的。如果您查看这个结构体的源码，那么就可以看到它实现了 Hashable 和 Equatable 两个协议，因此排序和唯一化（uniquing）PhotoInfo 对象仍会是一个比较快的操作。
        photoJsons.forEach {
          guard let nsfw = $0["nsfw"] as? Bool,
            let id = $0["id"] as? Int,
            let url = $0["image_url"] as? String,
            nsfw == false else {
              return
          }
          
          // 8 如果有人在我们滚动前向 500px.com 网站上传了新的图片，那么您所获得的新的一批照片将可能会包含一部分已下载的图片。这就是为什么我们定义 var photos = Set<PhotoInfo>() 为一个集合。由于集合内的项目必须唯一，因此重复的图片不会再次出现。
          self.photos.insert(PhotoInfo(id: id, url: url))
        }
        
        // 9 这里我们创建了一个 IndexPath 对象的数组，并将其插入到 collectionView 当中。
        let indexPaths = (lastItemCount..<self.photos.count).map {
          IndexPath(item: $0, section: 0)
        }
        
        // 10 在集合视图中插入项目，请在主队列中完成该操作，因为所有的 UIKit 操作都必须运行在主队列中。       
        DispatchQueue.main.async {
          self.collectionView?.insertItems(at: indexPaths)
        }
        
        self.currentPage += 1
      }
      
      self.populatingPhotos = false
    }
  }
  
  private dynamic func handleRefresh() {
    
  }
}

class PhotoBrowserCollectionViewCell: UICollectionViewCell {
  fileprivate let imageView = UIImageView()
  
  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    backgroundColor = UIColor(white: 0.1, alpha: 1.0)
    
    imageView.frame = bounds
    addSubview(imageView)
  }
}

class PhotoBrowserCollectionViewLoadingCell: UICollectionReusableView {
  fileprivate let spinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
  
  required init?(coder aDecoder: NSCoder) {
    super.init(coder: aDecoder)
  }
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    
    spinner.startAnimating()
    spinner.center = center
    addSubview(spinner)
  }
}
