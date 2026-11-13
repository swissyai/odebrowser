using OdeCore.Contracts;

namespace OdeCore.Application;

internal sealed partial class Device {
    #region Variables

    private IReadOnlyList<SetupImportOutcome> importOutcomes = [];
    internal IReadOnlyList<SetupImportOutcome> ImportOutcomes { get { lock (gate) return importOutcomes; } }

    #endregion

    #region Actions - Import outcomes

    /// Save before returning: a failure to record a started attempt must stop
    /// the platform before it mutates the session, cookies or Keychain.
    internal void KeepImportOutcome(SetupImportOutcome outcome) {
        ArgumentNullException.ThrowIfNull(outcome);
        lock (gate) {
            var previous = importOutcomes;
            var existing = previous.FirstOrDefault(item => item.Id == outcome.Id);
            if (existing?.Status == SetupImportOutcomeStatus.Imported) return;
            importOutcomes = existing is null ? [.. previous, outcome]
                : [.. previous.Select(item => item.Id == outcome.Id ? outcome : item)];
            try { storage?.SaveDevice(Records()); } catch (StorageException error) {
                importOutcomes = previous;
                throw new Rejected(new SaveFailed(error.Reason));
            } catch {
                importOutcomes = previous;
                throw;
            }
        }
    }

    internal void SetImportExtensionOutcome(Guid outcomeId, string extensionId, Guid spaceId, SetupImportExtensionStatus status) {
        lock (gate) {
            var previous = importOutcomes;
            var receipt = previous.FirstOrDefault(item => item.Id == outcomeId && item.Status == SetupImportOutcomeStatus.Imported);
            if (receipt is null || status == SetupImportExtensionStatus.Pending) return;
            var revised = receipt.Extensions.Select(item => item.ExtensionId == extensionId && item.SpaceId == spaceId
                && item.Status == SetupImportExtensionStatus.Pending ? item with { Status = status } : item).ToArray();
            if (revised.SequenceEqual(receipt.Extensions)) return;
            importOutcomes = [.. previous.Select(item => item.Id == outcomeId ? receipt with { Extensions = revised } : item)];
            try { storage?.SaveDevice(Records()); } catch (StorageException error) {
                importOutcomes = previous;
                throw new Rejected(new SaveFailed(error.Reason));
            } catch {
                importOutcomes = previous;
                throw;
            }
        }
    }

    #endregion
}
