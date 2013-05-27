--- Mockagne - Lua Mock Library
-- https://github.com/PunchWolf/mockagne
--
-- @copyright PunchWolf
-- @author Janne Sinivirta
-- @author Marko Pukari
module(..., package.seeall);

local latest_invoke = {}

function deepcompare(t1,t2,ignore_mt)
    local ty1 = type(t1)
    local ty2 = type(t2)

    if ty1 ~= ty2 then return false end
    --if objects are same or have same memory address
    if(t1 == t2) then return true end
    -- non-table types can be directly compared
    if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end

    -- as well as tables which have the metamethod __eq
    local mt = getmetatable(t1)
    if not ignore_mt and mt and mt.__eq then return t1 == t2 end

    for k1,v1 in pairs(t1) do
        local v2 = t2[k1]
        if v2 == nil or not deepcompare(v1,v2) then return false end
    end
    for k2,v2 in pairs(t2) do
        local v1 = t1[k2]
        if v1 == nil or not deepcompare(v1,v2) then return false end
    end

    return true
end


local function compareToAnyType(any, value)
    if not any.itemType then return true end
    if type(value) == "table" and value.anyType and any.itemType == value.itemType then return true end
    if any.itemType == type(value) then return true end

    return false
end

local function anyTypeMatch(v1, v2)
    if type(v1) == "table" and v1.anyType then
        if compareToAnyType(v1, v2) then return true end
    end

    if type(v2) == "table" and v2.anyType then
        if compareToAnyType(v2, v1) then return true end
    end

    return false
end

local function compareValues(v1, v2, strict)
    if v1 == v2 then
        return true
    end

    if not strict then
        if anyTypeMatch(v1, v2) then return true, true end -- second true implies that anytypes were used
    end
    if type(v1) ~= type(v2) then return false end

    return deepcompare(v1, v2)
end

local function compareArgs(args1, args2, strict)
    if #args1 ~= #args2 then return false end

    local anyTypesUsed = false
    for i, v1 in ipairs(args1) do
        local match, anyUsed = compareValues(v1, args2[i], strict)
        if not match then
            return false
        end
        if anyUsed then anyTypesUsed = true end
    end
    return true, anyTypesUsed
end

local function getReturn(self, method, ...)
    local args = {...}

    for i = 1, #self.expected_returns do
        local candidate = self.expected_returns[i]
        if (candidate.mock == self and candidate.key == method and compareArgs(args, candidate.args)) then
            if candidate.returnvalue.isPacked then
                return unpack(candidate.returnvalue.args)
            else
                return candidate.returnvalue
            end
        end
    end
    return nil
end

local function find_invoke(mock, method, expected_call_arguments, strict)
    local stored_calls = mock.stored_calls
    for i = 1, #stored_calls do
        local invocation = stored_calls[i]
        if (invocation.key == method and compareArgs(invocation.args, expected_call_arguments, strict)) then
            return stored_calls[i], i
        end
    end
end

local function capture(reftable, refkey)
    return function(...)
        local args = {...}

        local captured = { key = refkey, args = args, count = 1 }
        latest_invoke = { mock = reftable, key = refkey, args = args }

        local found = find_invoke(reftable, refkey, args, true)
        if (found) then
            found.count = found.count + 1
        else
            table.insert(reftable.stored_calls, captured)
        end
        return getReturn(reftable, refkey, ...)
    end
end

local function remove_invoke(mock, method, ...)
    local args = {...}
    local found, i = find_invoke(mock, method, args, true)
    if found then
        if (found.count > 1) then found.count = found.count - 1
        else table.remove(mock.stored_calls, i) end
    end
end

local function expect(self, method, returnvalue, ...)
    local args = {...}
    local expectation = { mock = self, key = method, returnvalue = returnvalue, args = args }

    table.insert(self.expected_returns, expectation)
end

local function thenAnswer(...)
    local answer = {}
    answer.isPacked = true
    answer.args = arg
    latest_invoke.mock:expect(latest_invoke.key, answer, unpack(latest_invoke.args))
    remove_invoke(latest_invoke.mock, latest_invoke.key, unpack(latest_invoke.args))
end

local function getName(self)
    return self.mockname
end

--- Verify that a given invocation happened
function verify(mockinvoke)
    remove_invoke(latest_invoke.mock, latest_invoke.key, unpack(latest_invoke.args)) -- remove invocation made for verify
    local stored_calls = latest_invoke.mock.stored_calls
    for i = 1, #stored_calls do
        invocation = stored_calls[i]
        if invocation.key == latest_invoke.key and compareArgs(invocation.args, latest_invoke.args) then
            return true
        end
    end
    error("No invocation made")
end

--- Returns a mock instance
-- @param name name for the mock (optional)
-- @return mock instance
function getMock(name)
    mock = { stored_calls = {}, expected_returns = {} }

    mt = { __index = capture }
    setmetatable(mock, mt)
    mock.expect = expect
    mock.getName = getName

    mock.mockname = name or ""
    mock.type = "mock"

    return mock
end

--- Used for teaching mock to return values with specific invocation
-- @param fcall function call expected to have a return value
-- @return table with thenAnswer function that is used to set the return value
function when(fcall)
    return { thenAnswer = thenAnswer }
end

--- Used to describe calls to mocks with parameters that don't matter (ie. can be any type)
function anyType(item)
    local mockType = {}
    mockType.anyType = true

    if item then
        mockType.itemType = type(item)
    end

    return mockType
end
