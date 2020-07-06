//
//  RiskCalculationController.swift
//  CoronaContact
//

import ExposureNotification
import Foundation
import Resolver

enum RiskCalculationError: Error {
    case exposureDetectionFailed(Error)
    case exposureInfoUnavailable(Error)
    case cancelled
    case noResult
}

typealias RiskCalculationResult = [Date: DiagnosisType]

final class RiskCalculationController {
    typealias CompletionHandler = ((Result<RiskCalculationResult, RiskCalculationError>) -> Void)

    private lazy var queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private let log = ContextLogger(context: LoggingContext.riskCalculation)
    private var completionHandler: CompletionHandler?
    private var riskCalculationResult = RiskCalculationResult()

    func processBatches(_ batches: [UnzippedBatch], completionHandler: @escaping CompletionHandler) {
        guard let operation = processFullBatch(batches) else {
            return
        }
        riskCalculationResult = RiskCalculationResult()
        self.completionHandler = completionHandler
        log.debug("Start processing full batch.")

        operation.completionBlock = { [weak self] in
            guard let self = self, let result = operation.result else {
                return
            }

            switch result {
            case let .success(.sevenDays(lastExposureDate, isEnoughRisk)) where isEnoughRisk:
                self.log.debug("""
                Successfully processed the full seven days batch which poses a risk. \
                Start processing daily batches going back from the last exposure date: \(lastExposureDate).
                """)
                self.processDailyBatches(batches, before: lastExposureDate)
            case .success(.sevenDays):
                self.log.debug("Successfully processed the full seven days batch which does not pose a risk.")
                self.completionHandler?(.success(self.riskCalculationResult))
            case let .success(.fourteenDays(dailyExposure)) where dailyExposure != nil:
                self.log.debug("Successfully processed the full fourteen days batch and detected an exposure.")
                self.completionHandler?(.success(self.riskCalculationResult))
            case .success(.fourteenDays):
                self.log.debug("Successfully processed the full fourteen days batch which does not pose a risk.")
                self.completionHandler?(.success(self.riskCalculationResult))
            case let .failure(error):
                self.log.error("Failed to process full batch due to an error: \(error)")
            }
        }

        queue.addOperation(operation)
    }

    private func processFullBatch(_ batches: [UnzippedBatch]) -> DetectExposuresOperation? {
        guard let fullBatch = batches.full else {
            log.warning("Unexpectedly found no full batch.")
            return nil
        }

        let operation = DetectExposuresOperation(diagnosisKeyURLs: fullBatch.urls, batchType: fullBatch.type)
        operation.handleDailyExposure = { [weak self] exposure, date in self?.storeDailyExposure(exposure, at: date) }

        return operation
    }

    private func processDailyBatches(_ batches: [UnzippedBatch], before date: Date) {
        let normalize = { (date: Date) in
            Calendar.current.startOfDay(for: date)
        }
        let dailyBatches = batches
            .filter { $0.type == .daily }
            .filter { normalize($0.interval.date) <= normalize(date) }
            .sorted { $0.interval.date > $1.interval.date }

        let operations: [DetectDailyExposuresOperation] = dailyBatches.map { batch in
            let operation = DetectDailyExposuresOperation(diagnosisKeyURLs: batch.urls, date: batch.interval.date)
            operation.completionBlock = handleCompletion(of: operation, date: batch.interval.date)
            operation.handleDailyExposure = { [weak self] exposure, date in self?.storeDailyExposure(exposure, at: date) }
            return operation
        }

        zip(operations, operations.dropFirst()).forEach { lhs, rhs in
            rhs.addDependency(lhs)
        }

        let completeOperation = completeRiskCalculation(after: operations)
        let allOperations = operations + [completeOperation]

        queue.addOperations(allOperations, waitUntilFinished: false)
    }

    private func completeRiskCalculation(after operations: [DetectDailyExposuresOperation]) -> RiskCalculationCompleteOperation {
        let completeOperation = RiskCalculationCompleteOperation()
        operations.forEach(completeOperation.addDependency)
        completeOperation.completionBlock = handleCompletion(of: completeOperation)

        return completeOperation
    }

    private func storeDailyExposure(_ dailyExposure: DailyExposure, at date: Date) {
        guard let diagnosisType = dailyExposure.diagnosisType else {
            return
        }
        riskCalculationResult[date] = diagnosisType
    }

    private func handleCompletion(of operation: DetectDailyExposuresOperation, date: Date) -> () -> Void {
        // swiftformat:disable:next redundantReturn
        return {
            guard let result = operation.result else {
                self.log.warning("Unexpectedly found no result for \(operation) for the daily batch at date \(date).")
                self.completionHandler?(.failure(.noResult))
                self.queue.cancelAllOperations()
                return
            }

            switch result {
            case let .success(dailyExposure) where dailyExposure.diagnosisType != nil:
                let diagnosisType = dailyExposure.diagnosisType!
                self.log.debug("Successfully processed daily batch at \(date) with diagnosis type: \(diagnosisType).")
            case .success:
                self.log.debug("Skipping daily batch at \(date), because it doesn't have a diagnosis type.")
            case let .failure(error):
                self.log.error("Failed to process daily batch at \(date) due to an error: \(error)")
                self.completionHandler?(.failure(error))
            }
        }
    }

    private func handleCompletion(of operation: RiskCalculationCompleteOperation) -> () -> Void {
        // swiftformat:disable:next redundantReturn
        return {
            self.log.debug("Successfully completed the risk calculation with result: \(self.riskCalculationResult)")
            self.completionHandler?(.success(self.riskCalculationResult))
        }
    }
}

private extension Array where Element == UnzippedBatch {
    var full: UnzippedBatch? {
        first {
            $0.type == .fullSevenDays || $0.type == .fullFourteenDays
        }
    }
}
