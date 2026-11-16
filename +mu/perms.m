function P = perms(N, k)
%PERMS  All possible k-element permutations from N elements.
%
%   P = mu.perms(N, k)
%
%   N : positive integer; the source elements are 1:N.
%   k : permutation length, 1 <= k <= N.
%
%   P : nchoosek(N,k)*k!-by-k matrix, one k-permutation per row.
%       Rows are grouped by ascending combination of 1:N; within each
%       combination the rows enumerate every ordering of that combination.
%       Use this instead of the built-in perms(), which permutes the whole
%       input and therefore cannot produce partial-length permutations.
%
%   EXAMPLES:
%       mu.perms(4, 2)   % 12-by-2, all ordered pairs from 1:4
%       mu.perms(3, 3)   % 6-by-3, same as perms(1:3)
%
%   See also mu.tuples, mu.nchoosek, perms.

narginchk(2, 2);

validateattributes(N, {'numeric'}, {'scalar', 'positive', 'integer'}, mfilename, 'N', 1);
validateattributes(k, {'numeric'}, {'scalar', 'positive', 'integer', '<=', N}, mfilename, 'k', 2);

combos = nchoosek(1:N, k);
nCombo = size(combos, 1);

P = zeros(nCombo * factorial(k), k);
row = 0;
for c = 1:nCombo
    p = localPermute(combos(c, :));
    P(row + (1:size(p, 1)), :) = p;
    row = row + size(p, 1);
end
end

function p = localPermute(v)
%LOCALPERMUTE  Every ordering of the row vector v (factorial(numel(v)) rows).
n = numel(v);
if n == 1
    p = v;
    return
end

p = zeros(factorial(n), n);
row = 0;
for i = 1:n
    rest = v([1:i-1, i+1:n]);
    sub = localPermute(rest);
    nSub = size(sub, 1);
    p(row + (1:nSub), :) = [repmat(v(i), nSub, 1), sub];
    row = row + nSub;
end
end
