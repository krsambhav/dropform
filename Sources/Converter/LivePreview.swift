import Foundation

extension Store {
    func stopPreviews() {
        previewRevision += 1
        previewTask?.cancel()
        previewEngine?.cancel()
    }

    func schedulePreviews() {
        stopPreviews()
        let previous = previewTask
        let revision = previewRevision
        for index in jobs.indices where jobs[index].output == nil {
            jobs[index].previewBytes = nil
            let size = outputSize(jobs[index].input)
            jobs[index].previewState = size > 0 && size <= 10_000_000 && jobs[index].status != "Unavailable" ? "Waiting for preview…" : "Preview available for files under 10 MB"
        }
        guard !running && !toolRunning else { return }
        previewTask = Task { [weak self] in
            // Never overlap an old conversion with its replacement.
            await previous?.value
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self, !Task.isCancelled, self.previewRevision == revision else { return }
            let worker = ConversionEngine()
            self.previewEngine = worker
            for job in self.jobs where job.output == nil && job.previewState == "Waiting for preview…" {
                guard !Task.isCancelled, self.previewRevision == revision else { return }
                guard let index = self.jobs.firstIndex(where: { $0.id == job.id }) else { continue }
                self.jobs[index].previewState = "Calculating…"
                let format = self.compress ? canonicalFormat(job.input.pathExtension) : job.format
                let shrink = self.compress, dimension = self.maxDimension, strip = self.stripMetadata
                worker.reset()
                let timeout = Task {
                    do { try await Task.sleep(nanoseconds: 8_000_000_000); worker.cancel() } catch {}
                }
                let result = await Task.detached { () -> Result<Int64, Error> in
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dropform-preview-" + UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: folder) }
                    return Result {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let output = try worker.run(input: job.input, format: format, directory: folder, quality: Int(job.quality), compress: false, maxDimension: dimension, stripMetadata: strip)
                        return outputSize(output)
                    }
                }.value
                timeout.cancel()
                guard !Task.isCancelled, self.previewRevision == revision,
                      let current = self.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                switch result {
                case .success(let bytes):
                    self.jobs[current].previewBytes = bytes
                    self.jobs[current].previewState = shrink && bytes >= outputSize(job.input) ? "No reduction at this quality" : "Live preview"
                case .failure(let error):
                    self.jobs[current].previewState = error.localizedDescription == "Cancelled" ? "Preview took too long · run conversion" : error.localizedDescription
                }
            }
            self.previewEngine = nil
        }
    }
}
