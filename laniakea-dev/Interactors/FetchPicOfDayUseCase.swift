class FetchPicOfDayUseCase {
    private let repository: PicOfDayRepo

    init(repository: PicOfDayRepo) {
        self.repository = repository
    }

    func execute(completion: @escaping (Result<PicOfDay, Error>) -> Void) {
        repository.fetchPicOfDay(completion: completion)
    }
}
