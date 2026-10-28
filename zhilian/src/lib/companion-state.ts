export interface CompanionStateMutationEpoch {
  current: number;
}

/** Advanced before and after the IPC call, so snapshots taken before or during a mutation read as stale. */
export const mutateCompanionBridgeState = async <State,>(
  epoch: CompanionStateMutationEpoch,
  mutate: () => Promise<State>,
): Promise<State> => {
  epoch.current += 1;
  try {
    return await mutate();
  } finally {
    epoch.current += 1;
  }
};

export const companionStateRefreshIsCurrent = (
  epoch: CompanionStateMutationEpoch,
  refreshEpoch: number,
): boolean => epoch.current === refreshEpoch;

export const phonePairingManualCodeMode = (
  pairingOpen: boolean,
  pairingLink: string | null,
): "details" | "direct" | "hidden" => {
  if (!pairingOpen) return "hidden";
  // The six-digit code stays on screen. A preview or a phone without a camera
  // cannot scan the QR, and the code is the pairing credential.
  void pairingLink;
  return "direct";
};
