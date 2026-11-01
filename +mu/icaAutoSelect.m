function [keep, p, k] = icaAutoSelect(comp, topoInfo, windowICA, modelPath)
%ICA_AUTOSELECT  Predict which ICA components to remove, using the trained model.
%
%   keep = mu.icaAutoSelect(comp, topoInfo, windowICA, modelPath)
%
%   The model was trained on 108 historical recordings (labels taken from the
%   stored comp.ICs) plus 13 manually labelled recordings (n = 3868 ICs).
%   Decision rule: k = round(sum(p)), i.e. the expected number of removals,
%   then keep everything outside the k highest-probability components.
%
% Input:
%   comp      : FieldTrip component struct WITH comp.trial (IC time courses)
%   topoInfo  : EEGPos struct (for the frontal-channel fraction) or [] / array
%   windowICA : [start, end] in ms
%   modelPath : path to model_all.mat (default: D:\NeuroAgent\runs\ica_hist\model_all.mat)
%
% Output:
%   keep : row vector of IC indices to KEEP
%   p    : removal probability per IC
%   k    : number of ICs suggested for removal

if nargin < 4 || isempty(modelPath)
    modelPath = 'D:\NeuroAgent\runs\ica_hist\model_all.mat';
end
if ~isfile(modelPath)
    error('mu:icaAutoSelect:noModel', 'model file not found: %s', modelPath);
end
M = load(modelPath, 'rf', 'muX', 'sdX');

icMean = mu.calchMean(comp.trial);
icSE   = mu.calchStd(comp.trial);
icAll  = cat(2, comp.trial{:});
topo   = comp.topo;
nIC    = size(topo, 2);
nsample = size(icMean, 2);

t = linspace(windowICA(1), windowICA(2), nsample);
onWin   = t >= 0 & t <= 300;
baseWin = t >= -300 & t < 0;
lateWin = t >= 1000 & t <= 4000;

% frontal-channel fraction (0 when no electrode layout is available)
if isstruct(topoInfo) && isfield(topoInfo, 'channelNames')
    frontal = {'Fp1','Fp2','FP1','FP2','F7','F8','F3','F4','Fz'};
    fIdx = find(ismember(topoInfo.channelNames, frontal));
else
    fIdx = [];
end

nP = 100;
tq = linspace(windowICA(1), windowICA(2), nP);
meanR = interp1(t, icMean', tq)';
seR   = interp1(t, icSE',   tq)';
scl   = max(std(meanR, 0, 2), eps);
meanZ = meanR ./ scl;
seZ   = seR   ./ scl;
topoZ = topo ./ max(abs(topo), [], 1);
if size(topoZ, 1) < 32
    topoZ(:, end+1:32) = 0;
end

scal = zeros(nIC, 11);
for ic = 1:nIC
    m = icMean(ic, :); s = icSE(ic, :); v = abs(topo(:, ic));
    aOn   = max(abs(m(onWin)));
    aBase = max(abs(m(baseWin)));
    aLate = max(abs(m(lateWin)));
    scal(ic, 1)  = max(v);
    if isempty(fIdx) || sum(v) == 0
        scal(ic, 2) = 0;
    else
        scal(ic, 2) = sum(v(fIdx)) / sum(v);
    end
    scal(ic, 3)  = aOn / max(std(icAll(ic, :)), eps);
    scal(ic, 4)  = aOn / max(median(s(onWin)), eps);
    scal(ic, 5)  = median(s(onWin)) / max(aOn, eps);
    scal(ic, 6)  = median(s) / max(std(m), eps);
    scal(ic, 7)  = kurtosis(icAll(ic, :));
    scal(ic, 8)  = aOn / max(aLate, eps);
    scal(ic, 9)  = mean(abs(m(onWin)) < s(onWin));
    scal(ic, 10) = mean(abs(diff(m))) / max(std(m), eps);
    scal(ic, 11) = sum(abs(m) > 3 * max(std(m(baseWin)), eps));
end

X = [scal, topoZ', meanZ, seZ];
if size(X, 2) < 243
    X(:, end+1:243) = 0;
end
Xz = (X - M.muX) ./ M.sdX;
[~, sc] = predict(M.rf, Xz);
p = sc(:, 2);

k = max(1, min(nIC, round(sum(p))));
[~, ord] = sort(p, 'descend');
remove = sort(ord(1:k))';
keep = setdiff(1:nIC, remove);
end
