function badChs = neuracleBadChs(nbchan)
%NEURACLEBADCHS  Non-EEG (auxiliary) channels of a Neuracle recording.
%
%   badChs = mu.neuracleBadChs(nbchan)
%
%   Neuracle 64-channel montage (EEGPos_Neuracle64):
%       ch 1-59 : scalp EEG (Fpz ... O2)
%       ch 60-64 : ECG, HEOR, HEOL, VEOU, VEOL   -> excluded from EEG analysis
%   That is why the historical export scripts hard-coded opts.badChs = 60:64.
%
%   Neuracle 32-channel montage (EEGPos_Neuracle32) has 32 scalp channels and
%   NO auxiliary channel, so nothing is excluded. Hard-coding 60:64 there made
%   the index run past the end of the array (Q8 in OPEN_QUESTIONS.md).
%
%   NOTE: PHASE4_CHANGE_LIST.md P0-1 originally suggested 29:32 for a
%   32-channel system. That is deliberately NOT used: channels 29-32 are
%   PO4, Oz, O1, O2 on the Neuracle32 cap, i.e. real occipital electrodes the
%   paper needs. The user confirmed on 2026-11-01 that a 32-channel recording
%   returns [] (no auxiliary channels), which is what this table does.
%   If a particular 32-channel dataset does carry auxiliary channels, change
%   the table below rather than the call sites.

switch nbchan
    case 64
        badChs = 60:64;   % ECG, HEOR, HEOL, VEOU, VEOL
    case 32
        badChs = [];      % all 32 channels are scalp EEG
    otherwise
        badChs = [];      % unknown montage: assume nothing, warn the caller
        warning('mu:neuracleBadChs:unknownMontage', ...
            'Unrecognised Neuracle channel count (%d); badChs is left empty.', nbchan);
end
end
