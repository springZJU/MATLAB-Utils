function neighbours = neuracle32Neighbours()
%NEURACLE32NEIGHBOURS  Anatomical neighbours for the Neuracle 32-channel montage.
%
%   neighbours = mu.neuracle32Neighbours()
%
%   Returns a 1x32 struct array with fields 'label' and 'neighbch', in the same
%   channel order as EEGPos_Neuracle32:
%     Fp1 Fp2 Fpz F3 F4 F7 F8 FC1 FC2 FC5 FC6 Cz C3 C4 T7 T8 M1 M2
%     CP1 CP2 CP5 CP6 Pz P3 P4 P7 P8 PO3 PO4 Oz O1 O2
%
%   Use it with mu_interpolateBadChannels when EEGPos.neighbours is empty
%   (ft_prepare_neighbours fails for this montage because the layout carries
%   no usable 3-D coordinates).

labels = {'Fp1','Fp2','Fpz','F3','F4','F7','F8','FC1','FC2','FC5','FC6', ...
          'Cz','C3','C4','T7','T8','M1','M2','CP1','CP2','CP5','CP6', ...
          'Pz','P3','P4','P7','P8','PO3','PO4','Oz','O1','O2'};

nb = { ...
    [3 4 6], ...                    % 1  Fp1
    [3 5 7], ...                    % 2  Fp2
    [1 2 4 5], ...                  % 3  Fpz
    [1 3 8 10], ...                 % 4  F3
    [2 3 9 11], ...                 % 5  F4
    [1 4 10 15], ...                % 6  F7
    [2 5 11 16], ...                % 7  F8
    [4 10 12 13], ...               % 8  FC1
    [5 11 12 14], ...               % 9  FC2
    [6 8 13 15], ...                % 10 FC5
    [7 9 14 16], ...                % 11 FC6
    [8 9 13 14 19 20], ...          % 12 Cz
    [8 10 12 15 19 21 24], ...      % 13 C3
    [9 11 12 16 20 22 25], ...      % 14 C4
    [10 13 21 26], ...              % 15 T7
    [11 14 22 27], ...              % 16 T8
    [15 21], ...                    % 17 M1
    [16 22], ...                    % 18 M2
    [12 13 21 23 24], ...           % 19 CP1
    [12 14 22 23 25], ...           % 20 CP2
    [13 19 24 26], ...              % 21 CP5
    [14 20 25 27], ...              % 22 CP6
    [19 20 24 25 28 29 30], ...     % 23 Pz
    [13 19 21 23 25 26 28], ...     % 24 P3
    [14 20 22 23 24 27 29], ...     % 25 P4
    [15 21 24 28], ...              % 26 P7
    [16 22 25 29], ...              % 27 P8
    [23 24 29 30 31], ...           % 28 PO3
    [23 25 28 30 32], ...           % 29 PO4
    [23 28 29 31 32], ...           % 30 Oz
    [28 30 32], ...                 % 31 O1
    [29 30 31]};                    % 32 O2

neighbours = struct('label', labels, 'neighbch', nb);
end
