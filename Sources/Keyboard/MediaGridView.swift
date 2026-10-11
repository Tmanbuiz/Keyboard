import UIKit

/// A scrolling grid for emoji, GIF previews and stickers. A collection view keeps thousands of
/// emoji fast and light on memory, which matters inside a keyboard extension.
final class MediaGridView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum Item {
        case emoji(String, toned: Bool)
        case remoteImage(URL, label: String)
        case image(UIImage, label: String)
    }

    var items: [Item] = [] { didSet { collection.reloadData(); collection.setContentOffset(.zero, animated: false) } }
    var columns = 8
    var onSelect: ((Int) -> Void)?
    var onLongPress: ((Int, UIView) -> Void)?
    private let palette: KeyboardPalette
    private let collection: UICollectionView
    private static let imageCache = NSCache<NSURL, UIImage>()

    init(palette: KeyboardPalette) {
        self.palette = palette
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2; layout.minimumLineSpacing = 2
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        collection.backgroundColor = .clear
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
        let width = (collectionView.bounds.width - CGFloat(columns - 1) * 2) / CGFloat(columns)
        if case .emoji = items[indexPath.item] { return CGSize(width: floor(width), height: 40) }
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
    private var loading: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 28); label.textAlignment = .center
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
        loading?.cancel(); loading = nil; imageView.image = nil; label.text = nil
    }

    func configure(_ item: MediaGridView.Item, palette: KeyboardPalette, cache: NSCache<NSURL, UIImage>) {
        switch item {
        case .emoji(let emoji, let toned):
            label.isHidden = false; imageView.isHidden = true; badge.isHidden = true
            label.text = emoji; accessibilityLabel = emoji
            accessibilityHint = toned ? "Hold for skin tones" : nil
        case .image(let image, let text):
            label.isHidden = true; imageView.isHidden = false; badge.isHidden = true
            imageView.image = image; imageView.backgroundColor = palette.key.withAlphaComponent(0.4); accessibilityLabel = text
        case .remoteImage(let url, let text):
            label.isHidden = true; imageView.isHidden = false; badge.isHidden = false
            imageView.backgroundColor = palette.key; accessibilityLabel = text
            if let cached = cache.object(forKey: url as NSURL) { imageView.image = cached; return }
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                // A GIF decodes to its first frame, which keeps dozens of previews light on memory.
                guard let data, data.count < 3_000_000, let image = UIImage(data: data) else { return }
                cache.setObject(image, forKey: url as NSURL)
                DispatchQueue.main.async { self?.imageView.image = image }
            }
            loading = task; task.resume()
        }
    }
}
