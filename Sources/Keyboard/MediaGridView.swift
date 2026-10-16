import UIKit
import ImageIO

/// A scrolling grid for emoji, GIF previews and stickers. A collection view keeps thousands of
/// emoji fast and light on memory, which matters inside a keyboard extension.
final class MediaGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum Item {
        case emoji(String, toned: Bool, name: String? = nil)
        case remoteImage(URL, label: String)
        case image(UIImage, label: String)
    }

    var items: [Item] = [] { didSet { collection.reloadData(); collection.setContentOffset(.zero, animated: false); updateEmptyState() } }
    var columns = 8
    var adaptiveEmojiColumns = false
    var emptyMessage = "" { didSet { updateEmptyState() } }
    private var lastLayoutSize = CGSize.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            collection.collectionViewLayout.invalidateLayout()
        }
    }
    private func updateEmptyState() {
        guard items.isEmpty else { collection.backgroundView = nil; return }
        let label = UILabel(); label.text = emptyMessage; label.numberOfLines = 0
        label.textAlignment = .center; label.font = .systemFont(ofSize: 15); label.textColor = palette.text.withAlphaComponent(0.6)
        collection.backgroundView = label
    }
    var onSelect: ((Int) -> Void)?
    var onLongPress: ((Int, UIView) -> Void)?
    private let palette: KeyboardPalette
    private let collection: UICollectionView
    static let imageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>(); cache.totalCostLimit = 8_000_000; cache.countLimit = 60; return cache
    }()

    init(palette: KeyboardPalette) {
        self.palette = palette
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2; layout.minimumLineSpacing = 2
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        collection.register(MediaCell.self, forCellWithReuseIdentifier: "cell")
        collection.dataSource = self; collection.delegate = self
        collection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collection)
        NSLayoutConstraint.activate([collection.leadingAnchor.constraint(equalTo: leadingAnchor), collection.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     collection.topAnchor.constraint(equalTo: topAnchor), collection.bottomAnchor.constraint(equalTo: bottomAnchor)])
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        collection.addGestureRecognizer(hold)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! MediaCell
        cell.configure(items[indexPath.item], palette: palette, cache: Self.imageCache)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let count = adaptiveEmojiColumns ? max(6, min(12, Int(collectionView.bounds.width / 44))) : columns
        let width = max(1, (collectionView.bounds.width - CGFloat(count - 1) * 2) / CGFloat(count))
        if case .emoji = items[indexPath.item] { return CGSize(width: floor(width), height: 48) }
        return CGSize(width: floor(width), height: floor(width * 0.8))
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        UIDevice.current.playInputClick()
        onSelect?(indexPath.item)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let path = collection.indexPathForItem(at: gesture.location(in: collection)),
              let cell = collection.cellForItem(at: path) else { return }
        onLongPress?(path.item, cell)
    }
}

private final class MediaCell: UICollectionViewCell {
    private let label = UILabel()
    private let imageView = UIImageView()
    private let badge = UILabel()
    private var loading: Task<Void, Never>?
    private var representedURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 32); label.textAlignment = .center
        imageView.contentMode = .scaleAspectFill; imageView.clipsToBounds = true; imageView.layer.cornerRadius = 6
        badge.font = .systemFont(ofSize: 8, weight: .bold); badge.text = "GIF"; badge.textColor = .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.55); badge.textAlignment = .center
        badge.layer.cornerRadius = 3; badge.clipsToBounds = true
        for view in [imageView, label, badge] { contentView.addSubview(view) }
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds; imageView.frame = contentView.bounds.insetBy(dx: 1, dy: 1)
        badge.frame = CGRect(x: 4, y: contentView.bounds.height - 15, width: 22, height: 11)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loading?.cancel(); loading = nil; representedURL = nil; imageView.image = nil; label.text = nil
    }

    func configure(_ item: MediaGridView.Item, palette: KeyboardPalette, cache: NSCache<NSURL, UIImage>) {
        loading?.cancel(); loading = nil; representedURL = nil; imageView.image = nil
        switch item {
        case .emoji(let emoji, let toned, let name):
            label.isHidden = false; imageView.isHidden = true; badge.isHidden = true
            label.text = emoji; accessibilityLabel = name ?? emoji
            accessibilityHint = toned ? "Hold for skin tones" : nil
        case .image(let image, let text):
            label.isHidden = true; imageView.isHidden = false; badge.isHidden = true
            imageView.image = image; imageView.backgroundColor = palette.key.withAlphaComponent(0.4); accessibilityLabel = text
        case .remoteImage(let url, let text):
            label.isHidden = true; imageView.isHidden = false; badge.isHidden = false
            imageView.backgroundColor = palette.key; accessibilityLabel = text
            if let cached = cache.object(forKey: url as NSURL) { imageView.image = cached; return }
            guard GifService.isTrusted(url) else { return }
            representedURL = url
            loading = Task { [weak self] in
                do {
                    let (data, response) = try await BoundedHTTP.load(URLRequest(url: url), maximum: 3_000_000)
                    guard (200...299).contains(response.statusCode), !Task.isCancelled,
                          let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int,
                          let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 2048, height <= 2048, width * height <= 262_144,
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 256,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary) else { return }
                    let image = UIImage(cgImage: thumbnail)
                    guard !Task.isCancelled, let self, self.representedURL == url else { return }
                    cache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
                    self.imageView.image = image
                } catch { /* Failed/cancelled previews leave the placeholder intact. */ }
            }
        }
    }
}
