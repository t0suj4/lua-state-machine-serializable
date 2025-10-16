require("busted")

local machine = require("statemachine")
local _ = require("luassert.match")._

describe("Lua state machine framework", function()
    describe("A stop light", function()
        local fsm
        local stoplight = {
            { name = 'warn',  from = 'green',  to = 'yellow' },
            { name = 'panic', from = 'yellow', to = 'red'    },
            { name = 'calm',  from = 'red',    to = 'yellow' },
            { name = 'clear', from = 'yellow', to = 'green'  }
        }

        before_each(function()
            fsm = machine.create({ initial = 'green', events = stoplight, _handler_access = true })
        end)

        it("should start as green", function()
            assert.is_true(fsm:is('green'))
        end)

        it("should not let you get to the wrong state", function()
            assert.is_false(fsm:panic())
            assert.is_false(fsm:calm())
            assert.is_false(fsm:clear())
        end)

        it("should let you go to yellow", function()
            assert.is_true(fsm:warn())
            assert.is_true(fsm:is('yellow'))
        end)

        it("should tell you what it can do", function()
            assert.is_true(fsm:can('warn'))
            assert.is_false(fsm:can('panic'))
            assert.is_false(fsm:can('calm'))
            assert.is_false(fsm:can('clear'))
        end)

        it("should tell you what it can't do", function()
            assert.is_false(fsm:cannot('warn'))
            assert.is_true(fsm:cannot('panic'))
            assert.is_true(fsm:cannot('calm'))
            assert.is_true(fsm:cannot('clear'))
        end)

        it("should support checking states", function()
            assert.is_true(fsm:is('green'))
            assert.is_false(fsm:is('red'))
            assert.is_false(fsm:is('yellow'))
        end)

        it("should fire callbacks", function()
            local fsm = machine.create({
                initial = 'green',
                events = stoplight,
                _handler_access = true,
                callbacks = {
                    onbeforewarn = stub.new(),
                    onleavegreen = stub.new(),
                    onenteryellow = stub.new(),
                    onafterwarn = stub.new(),
                    onstatechange = stub.new(),
                }
            })

            fsm:warn()

            assert.spy(fsm.onbeforewarn).was_called_with(_, 'warn', 'green', 'yellow')
            assert.spy(fsm.onleavegreen).was_called_with(_, 'warn', 'green', 'yellow')

            assert.spy(fsm.onenteryellow).was_called_with(_, 'warn', 'green', 'yellow')
            assert.spy(fsm.onafterwarn).was_called_with(_, 'warn', 'green', 'yellow')
            assert.spy(fsm.onstatechange).was_called_with(_, 'warn', 'green', 'yellow')
        end)

        it("should complain about conflicting callbacks", function()
            assert.has.errors(function()
                local fsm = machine.create({
                    initial = 'green',
                    events = stoplight,
                    callbacks = {
                        onenteryellow = stub.new(),
                        onyellow = stub.new()
                    }
                })
            end)
        end)

        it("should fire handlers", function()
            fsm.onbeforewarn = stub.new()
            fsm.onleavegreen = stub.new()
            fsm.onenteryellow = stub.new()
            fsm.onafterwarn = stub.new()
            fsm.onstatechange = stub.new()

            fsm:warn()

            assert.spy(fsm.onbeforewarn).was_called_with(_, 'warn', 'green', 'yellow')
            assert.spy(fsm.onleavegreen).was_called_with(_, 'warn', 'green', 'yellow')

            assert.spy(fsm.onenteryellow).was_called_with(_, 'warn', 'green', 'yellow')
            assert.spy(fsm.onafterwarn).was_called_with(_, 'warn', 'green', 'yellow')
            assert.spy(fsm.onstatechange).was_called_with(_, 'warn', 'green', 'yellow')
        end)

        it("should complain about overwritten handlers", function()
            assert.has.errors(function()
                fsm.onenteryellow = stub.new()
                fsm.onyellow = stub.new()
            end)
        end)

        it("should accept additional arguments to handlers", function()
            fsm.onbeforewarn = stub.new()
            fsm.onleavegreen = stub.new()
            fsm.onenteryellow = stub.new()
            fsm.onafterwarn = stub.new()
            fsm.onstatechange = stub.new()

            fsm:warn('bar')

            assert.spy(fsm.onbeforewarn).was_called_with(_, 'warn', 'green', 'yellow', 'bar')
            assert.spy(fsm.onleavegreen).was_called_with(_, 'warn', 'green', 'yellow', 'bar')

            assert.spy(fsm.onenteryellow).was_called_with(_, 'warn', 'green', 'yellow', 'bar')
            assert.spy(fsm.onafterwarn).was_called_with(_, 'warn', 'green', 'yellow', 'bar')
            assert.spy(fsm.onstatechange).was_called_with(_, 'warn', 'green', 'yellow', 'bar')
        end)

        it("should use long handlers anyway", function()
            fsm.onyellow = stub.new()
            fsm.onwarn = stub.new()

            fsm:warn()

            assert.spy(fsm.onenteryellow).was_called_with(_, 'warn', 'green', 'yellow')
            assert.spy(fsm.onafterwarn).was_called_with(_, 'warn', 'green', 'yellow')
        end)

        it("should cancel the warn event from onleavegreen", function()
            fsm.onleavegreen = function(self, name, from, to) 
                return false
            end

            local result = fsm:warn()

            assert.is_false(result)
            assert.is_true(fsm:is('green'))
        end)

        it("should cancel the warn event from onbeforewarn", function()
            fsm.onbeforewarn = function(self, name, from, to) 
                return false
            end

            local result = fsm:warn()

            assert.is_false(result)
            assert.is_true(fsm:is('green'))
        end)

        it("pauses when async is passed", function()
            fsm.onleavegreen = function(self, name, from, to)
                return fsm.ASYNC
            end
            fsm.onenteryellow = function(self, name, from, to)
                return fsm.ASYNC
            end

            local result = fsm:warn()
            assert.is_true(result)
            assert.is_true(fsm:is('green'))
            assert.are_equal(fsm._state.currentTransitioningEvent, 'warn')
            assert.are_equal(fsm._state.asyncState, 'warnWaitingOnLeave')

            result = fsm:transition(fsm._state.currentTransitioningEvent)
            assert.is_true(result)
            assert.is_true(fsm:is('yellow'))
            assert.are_equal(fsm._state.currentTransitioningEvent, 'warn')
            assert.are_equal(fsm._state.asyncState, 'warnWaitingOnEnter')

            result = fsm:transition(fsm._state.currentTransitioningEvent)
            assert.is_true(result)
            assert.is_true(fsm:is('yellow'))
            assert.is_nil(fsm._state.currentTransitioningEvent)
            assert.are_equal(fsm._state.asyncState, fsm.NONE)
        end)

        it("should accept additional arguments to async handlers", function()
            fsm.onbeforewarn = stub.new()
            fsm.onleavegreen = spy.new(function(self, name, from, to, arg)
                return fsm.ASYNC
            end)
            fsm.onenteryellow = spy.new(function(self, name, from, to, arg)
                return fsm.ASYNC
            end)
            fsm.onafterwarn = stub.new()
            fsm.onstatechange = stub.new()

            fsm:warn('bar')
            assert.spy(fsm.onbeforewarn).was_called_with(_, 'warn', 'green', 'yellow', 'bar')
            assert.spy(fsm.onleavegreen).was_called_with(_, 'warn', 'green', 'yellow', 'bar')

            fsm:transition(fsm._state.currentTransitioningEvent)
            assert.spy(fsm.onenteryellow).was_called_with(_, 'warn', 'green', 'yellow', 'bar')

            fsm:transition(fsm._state.currentTransitioningEvent)
            assert.spy(fsm.onafterwarn).was_called_with(_, 'warn', 'green', 'yellow', 'bar')
            assert.spy(fsm.onstatechange).was_called_with(_, 'warn', 'green', 'yellow', 'bar')
        end)

        it("should properly transition when another event happens during leave async", function()
            local tempStoplight = {}
            for _, event in ipairs(stoplight) do
                table.insert(tempStoplight, event)
            end
            table.insert(tempStoplight, { name = "panic", from = "green", to = "red" })

            local fsm = machine.create({
                initial = 'green',
                events = tempStoplight
            })

            fsm.onleavegreen = function(self, name, from, to)
                return fsm.ASYNC
            end

            fsm:warn()

            local result = fsm:panic()
            local transitionResult = fsm:transition(fsm._state.currentTransitioningEvent)

            assert.is_true(result)
            assert.is_true(transitionResult)
            assert.is_nil(fsm._state.currentTransitioningEvent)
            assert.are_equal(fsm._state.asyncState, fsm.NONE)
            assert.is_true(fsm:is('red'))
        end)

        it("should properly transition when another event happens during enter async", function()
            fsm.onenteryellow = function(self, name, from, to)
                return fsm.ASYNC
            end

            fsm:warn()

            local result = fsm:panic()

            assert.is_true(result)
            assert.is_nil(fsm._state.currentTransitioningEvent)
            assert.are_equal(fsm._state.asyncState, fsm.NONE)
            assert.is_true(fsm:is('red'))
        end)

        it("should properly cancel the transition if asked", function()
            fsm = machine.create{initial = "green", events = stoplight, lax = true}
            fsm.onleavegreen = function(self, name, from, to)
                return fsm.ASYNC
            end

            fsm:warn()
            fsm:cancelTransition(fsm._state.currentTransitioningEvent)

            assert.is_nil(fsm._state.currentTransitioningEvent)
            assert.are_equal(fsm._state.asyncState, fsm.NONE)
            assert.is_true(fsm:is('green'))

            fsm.onleavegreen = nil
            fsm.onenteryellow = function(self, name, from, to)
                return fsm.ASYNC
            end

            fsm:warn()
            fsm:cancelTransition(fsm._state.currentTransitioningEvent)

            assert.is_nil(fsm._state.currentTransitioningEvent)
            assert.are_equal(fsm._state.asyncState, fsm.NONE)
            assert.is_true(fsm:is('yellow'))
        end)

        it("todot generates dot file (graphviz)", function()
            local _state
            assert.has_no_error(function()
                _state = fsm:todot('stoplight.dot')
            end)
            assert.is_equal(_state, io.open('stoplight.dot.ref'):read('*a'))
        end)
    end)

    describe("A monster", function()
        local fsm
        local monster = {
            { name = 'eat',  from = 'hungry',                                to = 'satisfied' },
            { name = 'eat',  from = 'satisfied',                             to = 'full'      },
            { name = 'eat',  from = 'full',                                  to = 'sick'      },
            { name = 'rest', from = {'hungry', 'satisfied', 'full', 'sick'}, to = 'hungry'    }
        }

        before_each(function()
            fsm = machine.create({ initial = 'hungry', events = monster })
        end)

        it("can eat unless it is sick", function()
            assert.is_true(fsm:is('hungry'))
            assert.is_true(fsm:can('eat'))
            fsm:eat()
            assert.is_true(fsm:is('satisfied'))
            assert.is_true(fsm:can('eat'))
            fsm:eat()
            assert.is_true(fsm:is('full'))
            assert.is_true(fsm:can('eat'))
            fsm:eat()
            assert.is_true(fsm:is('sick'))
            assert.is_false(fsm:can('eat'))
        end)

        it("can always rest", function()
            assert.is_true(fsm:is('hungry'))
            assert.is_true(fsm:can('rest'))
            fsm:eat()
            assert.is_true(fsm:is('satisfied'))
            assert.is_true(fsm:can('rest'))
            fsm:eat()
            assert.is_true(fsm:is('full'))
            assert.is_true(fsm:can('rest'))
            fsm:eat()
            assert.is_true(fsm:is('sick'))
            assert.is_true(fsm:can('rest'))
            fsm:rest()
            assert.is_true(fsm:is('hungry'))
        end)
    end)
    describe("async cancellation", function()
        local fsm
        before_each(function()
            fsm = machine.create{initial = "idle", events = {{ name = "go", from = "idle", to = "busy" }}, _handler_access = true}
            fsm.onleaveidle = spy.new(function() return fsm.ASYNC end)
            fsm.onenterbusy = stub.new()
        end)

        describe("state preservation", function()
            it("should restore state after cancellation mid-flight", function()
                assert.is_true(fsm:go())
                fsm:cancelTransition("go")

                local canAgain = fsm:can("go")
                assert.is_true(canAgain)
            end)

            it("does not advance to 'enter' after cancellation even if transition() is called again", function()
                assert.is_true(fsm:go())
                fsm:cancelTransition("go")

                fsm:transition("go")
                assert.spy(fsm.onenterbusy).was_not_called()
                assert.is_true(fsm:is("idle"))
            end)
        end)

        describe("argument preservation", function()
            it("should preserve arguments in leave", function()
                local A, B = {}, {}
                assert.is_true(fsm:go(A))
                fsm:cancelTransition("go")

                assert.spy(fsm.onleaveidle).was_called_with(_, "go", "idle", "busy", A)
                assert.spy(fsm.onenterbusy).was_not_called()
                assert.is_true(fsm:is("idle"))

                assert.is_true(fsm:go(B))
                fsm:cancelTransition("go")

                assert.spy(fsm.onleaveidle).was_called_with(_, "go", "idle", "busy", B)
                assert.spy(fsm.onenterbusy).was_not_called()
                assert.is_true(fsm:is("idle"))

                assert.is_true(fsm:go(A))
                fsm:transition("go")
                assert.spy(fsm.onleaveidle).was_called_with(_, "go", "idle", "busy", A)
                assert.spy(fsm.onenterbusy).was_called_with(_, "go", "idle", "busy", A)
            end)
        end)
    end)
end)
