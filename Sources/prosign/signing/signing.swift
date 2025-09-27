struct FileItem {
    var url: URL?
    var name: String { url?.lastPathComponent ?? "" }
}