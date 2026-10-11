import Combine
import SwiftUI

class PicOfDayViewModel: ObservableObject {
    @Published var picOfDay: PicOfDay?
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false
    private let fetchPicOfDayUseCase: FetchPicOfDayUseCase
    private var lastFetchDate: Date?
    private let cacheInterval: TimeInterval = 3600

    init(fetchPicOfDayUseCase: FetchPicOfDayUseCase) {
        self.fetchPicOfDayUseCase = fetchPicOfDayUseCase
    }

    func loadPicOfDay() {
        if isLoading { return }
        if let lastFetch = lastFetchDate, Date().timeIntervalSince(lastFetch) < cacheInterval {
            return
        }

        isLoading = true
        errorMessage = nil
        fetchPicOfDayUseCase.execute { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                switch result {
                case .success(let picOfDay):
                    self.picOfDay = picOfDay
                    self.lastFetchDate = Date()
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
