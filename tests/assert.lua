local M = {}

function M.assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assert_equal failed") .. ": expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
  end
end

return M

