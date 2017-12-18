import UIKit

@objc public protocol AddArticlesToReadingListDelegate: NSObjectProtocol {
    func viewControllerWillBeDismissed()
    @objc optional func addedArticleToReadingList(named name: String)
}

class AddArticlesToReadingListViewController: UIViewController {
    
    fileprivate let dataStore: MWKDataStore
    fileprivate let articles: [WMFArticle]
    
    @IBOutlet weak var navigationBar: UINavigationBar?
    @IBOutlet weak var addButton: UIBarButtonItem?
    @IBOutlet weak var closeButton: UIBarButtonItem?
    
    fileprivate var readingListsViewController: ReadingListsViewController?
    @IBOutlet weak var containerView: UIView!
    public weak var delegate: AddArticlesToReadingListDelegate?

    fileprivate var theme: Theme
    
    init(with dataStore: MWKDataStore, articles: [WMFArticle], theme: Theme) {
        self.dataStore = dataStore
        self.articles = articles
        self.theme = theme
        super.init(nibName: "AddArticlesToReadingListViewController", bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @IBAction func closeButtonPressed() {
        dismiss(animated: true, completion: nil)
        delegate?.viewControllerWillBeDismissed()
    }
    
    @IBAction func addButtonPressed() {
        let createReadingListViewController = CreateReadingListViewController(theme: self.theme)
        createReadingListViewController.delegate = readingListsViewController
        present(createReadingListViewController, animated: true, completion: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationBar?.topItem?.title = String.localizedStringWithFormat(WMFLocalizedString("add-articles-to-reading-list", value:"Add %1$@ articles to reading list", comment:"Title for the view in charge of adding articles to a reading list - %1$@ is replaced with the number of articles to add"), "\(articles.count)")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: nil, action: nil)
        
        readingListsViewController = ReadingListsViewController.init(with: dataStore, articles: articles)
        guard let readingListsViewController = readingListsViewController else {
            return
        }
        addChildViewController(readingListsViewController)
        readingListsViewController.view.frame = containerView.bounds
        readingListsViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(readingListsViewController.view)
        readingListsViewController.didMove(toParentViewController: self)
        readingListsViewController.addArticlesToReadingListDelegate = self
        apply(theme: theme)
    }
}

extension AddArticlesToReadingListViewController: AddArticlesToReadingListDelegate {
    func viewControllerWillBeDismissed() {
        delegate?.viewControllerWillBeDismissed()
    }
    
    func addedArticleToReadingList(named name: String) {
        delegate?.addedArticleToReadingList?(named: name)
    }
}

extension AddArticlesToReadingListViewController: Themeable {
    func apply(theme: Theme) {
        self.theme = theme
        guard viewIfLoaded != nil else {
            return
        }

        navigationBar?.barTintColor = theme.colors.chromeBackground
        navigationBar?.tintColor = theme.colors.chromeText
        navigationBar?.titleTextAttributes = theme.navigationBarTitleTextAttributes
        view.tintColor = theme.colors.link
        navigationBar?.setBackgroundImage(theme.navigationBarBackgroundImage, for: .default)
        view.backgroundColor = theme.colors.chromeBackground
        readingListsViewController?.apply(theme: theme)
    }
}