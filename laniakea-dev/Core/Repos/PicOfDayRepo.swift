protocol PicOfDayRepo {
    func fetchPicOfDay(completion: @escaping (Result<PicOfDay, Error>) -> Void)
}
