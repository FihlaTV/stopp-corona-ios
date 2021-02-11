//
//  ReportHealthStatusFlowController.swift
//  CoronaContact
//

import ExposureNotification
import Foundation
import Resolver

class ReportHealthStatusFlowController {
    @Injected private var exposureManager: ExposureManager
    @Injected private var networkService: NetworkService
    @Injected private var localStorage: LocalStorage

    typealias Completion<Success> = (Result<Success, ReportError>) -> Void

    enum ReportError: Error {
        case unknown
        case tanConfirmation(NetworkService.DisplayableError)
        case submission(NetworkService.TracingKeysError)
    }

    private var tanUUID: String?
    private var verification: Verification?
    var personalData: PersonalData?

    func tanConfirmation(personalData: PersonalData, completion: @escaping Completion<Void>) {
        self.personalData = personalData

        networkService.requestTan(mobileNumber: personalData.mobileNumber) { [weak self] result in
            switch result {
            case let .success(response):
                self?.tanUUID = response.uuid
                completion(.success(()))
            case let .failure(error):
                completion(.failure(.tanConfirmation(error)))
            }
        }
    }

    func statusReport(tanNumber: String) {
        guard let tanUUID = tanUUID else {
            return
        }

        verification = Verification(uuid: tanUUID, authorization: tanNumber)
    }

    func submit(from startDate: Date, untilIncluding endDate: Date, diagnosisType: DiagnosisType, isRevoken: Bool = false, completion: @escaping Completion<Void>) {
        guard let verification = verification else {
            failSilently(completion)
            return
        }
        
        var keysFromDate = startDate
        var keysUntilDate = endDate
        
        if !isRevoken, let missingUploadedKeysAt = localStorage.missingUploadedKeysAt {
            keysFromDate = missingUploadedKeysAt
            keysUntilDate = missingUploadedKeysAt
        }

        exposureManager.getKeysForUpload(from: keysFromDate, untilIncluding: keysUntilDate, diagnosisType: diagnosisType) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case let .success(temporaryExposureKeys):
                let tracingKeys = TracingKeys(
                    temporaryExposureKeys: temporaryExposureKeys,
                    diagnosisType: diagnosisType,
                    verificationPayload: verification
                )
                
                if !isRevoken {
                    self.localStorage.missingUploadedKeysAt = temporaryExposureKeys.contains(where: { $0.intervalNumber == Date().intervalNumber }) ? nil : Date()
                }
                
                LoggingService.debug("uploading \(diagnosisType)", context: .exposure)
                self.sendTracingKeys(tracingKeys, completion: completion)
            case .failure:
                completion(.failure(.unknown))
            }
        }
    }

    private func sendTracingKeys(_ tracingKeys: TracingKeys, completion: @escaping Completion<Void>) {
        networkService.sendTracingKeys(tracingKeys) { result in
            switch result {
            case .success:
                completion(.success(()))
            case let .failure(error):
                completion(.failure(.submission(error)))
            }
        }
    }

    private func failSilently<Success>(_ completion: @escaping Completion<Success>) {
        completion(.failure(.unknown))
    }
}
