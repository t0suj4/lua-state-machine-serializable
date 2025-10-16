--- Finite State Machine.
-- A port of `javascript-state-machine` by `jakesgordon`
-- https://github.com/jakesgordon/javascript-state-machine
-- @module statemachine
-- @alias machine

-- https://github.com/kyleconroy/lua-state-machine

-- Copyright (c) 2012 Kyle Conroy
-- Copyright (c) 2025 t0suj4
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.



---@class Fsm
local machine = {}
machine.__index = machine

---@alias None "none"
---@alias Async "async"

--- A constant representing no active asynchronous operation.
--- @type None
local NONE = "none"

--- A constant to be returned from a callback to indicate an asynchronous operation.
--- This will pause the transition until `fsm:transition()` is called again.
--- @type Async
local ASYNC = "async"

-- Compatibility for Lua 5.1 vs 5.2+
local unpack = unpack or table.unpack

---@param handler EventCallback
---@param m Fsm
---@param params AnySerializableType[]
---@return Async|nil
local function call_handler(handler, m, params)
    if handler then
        return handler(m, unpack(params))
    end
end

---@param name string Event name
---@return fun(self: Fsm, ...: AnySerializableType)
local function create_transition(name)
    local function transition(self, ...)
        local state = self._state
        if state.asyncState == NONE then
            local can, to = self:can(name)
            local from = state.current
            if not can then return false end
            state.to = to

            state.params = { name, from, to, ...}
            state.currentTransitioningEvent = name

            local beforeReturn = call_handler(self["onbefore" .. name], self, state.params)
            local leaveReturn = call_handler(self["onleave" .. from], self, state.params)

            if beforeReturn == false or leaveReturn == false then
                return false
            end

            state.asyncState = name .. "WaitingOnLeave"

            if leaveReturn ~= ASYNC then
                transition(self, ...)
            end

            return true
        elseif state.asyncState == name .. "WaitingOnLeave" then
            local to = state.to
            state.current = to

            local enterReturn = call_handler(self["onenter" .. to], self, state.params)

            state.asyncState = name .. "WaitingOnEnter"

            if enterReturn ~= ASYNC then
                transition(self, ...)
            end

            return true
        elseif state.asyncState == name .. "WaitingOnEnter" then
            call_handler(self["onafter" .. name], self, state.params)
            call_handler(self["onstatechange"], self, state.params)
            state.asyncState = NONE
            state.currentTransitioningEvent = nil
            return true
        else
            if string.find(state.asyncState, "WaitingOnLeave") or string.find(state.asyncState, "WaitingOnEnter") then
                state.asyncState = NONE
                transition(self, ...)
                return true
            end
        end

        state.currentTransitioningEvent = nil
        return false
    end

    return transition
end

--- @type table<string, boolean>
local allStates

--- @type boolean
local haveWildcard

--- @param t table<string, string>
--- @param name string
function add_event_handler_names(t, name)
    t["onbefore" .. name] = "onbefore" .. name
    t["onafter" .. name] = "onafter" .. name
    t["on" .. name] = "onafter" .. name
end

--- @param t table<string, string>
--- @param from string
function add_from_handler_names(t, from)
    if from == "*" then
        haveWildcard = true
    else
        allStates[from] = true
        t["onleave" .. from] = "onleave" .. from
    end
end

--- @param t table<string, string>
--- @param to string
function add_to_handler_names(t, to)
    allStates[to] = true
    t["onenter" .. to] = "onenter" .. to
    t["on" .. to] = "onenter" .. to
end

--- @param t table<string, string>
function settle_wildcards(t)
    if haveWildcard then
        for k in pairs(allStates) do
            t["onleave" .. k] = "onleave" .. k
        end
    end
end

--- @param map table<string, string>
--- @param callbacknames table<string, string>
--- @param event EventDefinition
local function add_to_map(map, callbacknames, event)
    if type(event.from) == 'string' then
        map[event.from] = event.to
        add_from_handler_names(callbacknames, event.from)
    else
        for _, from in ipairs(event.from) do
            map[from] = event.to
            add_from_handler_names(callbacknames, from)
        end
    end
    add_to_handler_names(callbacknames, event.to)
end

--- @param v any
function is_callable_or_nil(v)
    local t = type(v)
    if t == "function" or t == "nil" then
        return true, t
    elseif t == "table" then
        local mt = getmetatable(v)
        if type(mt.__call) == "function" then
            return true, t
        end
    end
    return false, t
end

function machine.__newindex(t, k, v)
    if t._sealed then
        error("Cannot modify sealed object")
    end
    local name = t._callbacks[k]
    if name then
        local valid, typ = is_callable_or_nil(v)
        if not valid then
            error("Unexpected handler: " .. k .. " type: " .. typ)
        elseif t[name] ~= nil and not t._lax then
            error("Attempted to overwrite event handler: " .. name)
        end
        rawset(t, name, v)
    elseif t._lax then
        rawset(t, k, v)
    else
        error("No valid callback named: " .. k)
    end
end

---@class EventDefinition
---@field name string Event name
---@field from string|string[] States the event transitions from or "*" for any state
---@field to string State the event transitions to
local _

---@alias SerializableTable table
---@alias SerializableUserData userdata
---@alias AnySerializableType SerializableTable|SerializableUserData|string|number|boolean|nil
---@alias EventCallback fun(fsm: Fsm, event: string, from: string, to: string, ...: AnySerializableType): Async|void
---@alias EventCallbacks table<string, EventCallback>

---@class FsmOptions
---@field public initial string|nil default "none", Initial state
---@field public events EventDefinition[] Valid states and events of the machine
---@field public callbacks EventCallbacks State transition callbacks
---@field public state table|nil default {}, Table to hold the machine state
---@field public lax boolean|nil default false, True will allow storing data on the machine object and replacing callbacks
---@field public seal boolean|nil default false, True will prevent any modifications
local _

---@alias EventTriggers table<string, fun(self: self, ...: AnySerializableType)>

--- Creates a new state machine.
--- @param options FsmOptions The options for the state machine.
--- @return Fsm|EventCallbacks|EventTriggers The new state machine object.
--- @usage
--- local fsm = statemachine.create{
---   initial = 'green',
---   events = {
---     { name = 'warn', from = 'green', to = 'yellow' },
---     { name = 'panic', from = 'yellow', to = 'red' },
---     { name = 'calm', from = 'red', to = 'yellow' },
---     { name = 'clear', from = 'yellow', to = 'green' }
---   },
---   callbacks = {
---     onpanic = function(fsm, event, from, to)
---       -- Handle panic
---     end,
---   }
--- }
function machine.create(options)
    assert(options.events)

    local fsm = {}

    local state = options.state or {}
    fsm._state = state
    fsm._options = options
    fsm._callbacks = {onstatechange = "onstatechange"}
    fsm._lax = options.lax or false
    fsm._sealed = false

    state.current = state.current or options.initial or 'none'
    state.asyncState = state.asyncState or NONE

    -- upvalues
    haveWildcard = false
    allStates = {}
    allStates[state.current] = true

    state.events = state.events or options.events

    fsm.events = {}
    for _, event in ipairs(state.events or {}) do
        local name = event.name
        fsm[name] = fsm[name] or create_transition(name)
        fsm.events[name] = fsm.events[name] or { map = {} }
        add_event_handler_names(fsm._callbacks, name)
        add_to_map(fsm.events[name].map, fsm._callbacks, event)
    end
    settle_wildcards(fsm._callbacks)
    setmetatable(fsm, machine)

    for name, callback in pairs(options.callbacks or {}) do
        fsm[name] = callback
    end
    if options.seal then
        fsm:seal()
    end

    return fsm
end

--- Seals the state machine, preventing any further modifications.
function machine:seal()
    self._sealed = true
    self._callbacks = nil
end

---Checks if the current state is the given state
---@param state string The state to check against
---@return boolean True if the current state matches
function machine:is(state)
    return self._state.current == state
end

--- Checks if an event can be triggered in the current state.
--- @param e string The name of the event.
--- @return boolean, string True if the event can be triggered, Next state if it can
function machine:can(e)
    local event = self.events[e]
    local to = event and event.map[self._state.current] or event.map['*']
    return to ~= nil, to
end

--- Checks if an event can be triggered in the current state.
--- @param e string The name of the event.
--- @return boolean, string True if the event cannot be triggered, Next state if it can
--- @see Fsm#can
function machine:cannot(e)
    return not self:can(e)
end

--- Generates a Graphviz dot file representation of the state machine.
--- @return string The dot file content as a string.
function machine:todot()
    local text = {}
    table.insert(text, 'digraph {\n')
    local transition = function(event,from,to)
        table.insert(text, string.format('%s -> %s [label=%s];\n',from,to,event))
    end
    for _, event in pairs(self._options.events) do
        if type(event.from) == 'table' then
            for _, from in ipairs(event.from) do
                transition(event.name,from,event.to)
            end
        else
            transition(event.name,event.from,event.to)
        end
    end
    table.insert(text, '}\n')
    return table.concat(text)
end

--- Triggers a transition.
--- If an `onleave<state>` or `onenter<state>` callback returns `ASYNC`, the transition will be paused.
--- To resume a paused transition, call this method again with the same event name.
--- @param event string The name of the event to trigger
--- @return boolean Returns false if the transition is invalid or cancelled
--- @see Fsm#cancelTransition
function machine:transition(event)
    if self._state.currentTransitioningEvent == event then
        return self[self._state.currentTransitioningEvent](self) or false
    end
    return false
end

--- Cancels an ongoing asynchronous transition for the given event.
--- This will stop a pending transition that is waiting for `fsm:transition()` to be called again
--- @param event string The name of the event whose transition should be cancelled
--- @see Fsm#transition
function machine:cancelTransition(event)
    if self._state.currentTransitioningEvent == event then
        self._state.asyncState = NONE
        self._state.currentTransitioningEvent = nil
    end
end

machine.NONE = NONE
machine.ASYNC = ASYNC

return machine
