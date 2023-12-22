local flib_gui = require("__flib__/gui-lite")

script.on_init(function()
    global.tctrl_guis = {}
    global.train_stops = {}
    global.tctrl_data = {}
end)

script.on_event(defines.events.on_gui_opened, function(e)
    if e.gui_type == defines.gui_type.entity
        and e.entity
        and e.entity.valid
        and e.entity.type == "train-stop"
    then
        local train_stop = e.entity
        local tsid = train_stop.unit_number
        local player = game.players[e.player_index]

        if global.tctrl_guis[e.player_index] then
            global.tctrl_guis[e.player_index].gui.tctrl_window.destroy()
        end

        if not global.train_stops[tsid] then
            global.train_stops[tsid] = train_stop
        end

        if not global.tctrl_data[tsid] then
            global.tctrl_data[tsid] = {}
        end
        local this_data = global.tctrl_data[tsid]

        -- Only show our GUI when the train stop is connected to a circuit network.
        if not train_stop.get_circuit_network(defines.wire_type.red)
            and not train_stop.get_circuit_network(defines.wire_type.green)
        then
            return
        end

        local tctrl_gui = flib_gui.add(player.gui.relative, {
            {
                type = "frame",
                name = "tctrl_window",
                direction = "vertical",
                anchor = {
                    gui = defines.relative_gui_type.train_stop_gui,
                    position = defines.relative_gui_position.left
                },

                {
                    type = "flow",
                    name = "tctrl_titlebar",

                    {
                        type = "label",
                        style = "frame_title",
                        caption = "Train Control",
                        ignored_by_interaction = true,
                    },
                    -- Looks like we can't make this drag the train stop window since
                    -- we can't set the drag_target because the train stop window frame is
                    -- not accessible from Lua.
                    -- {
                    --     type = "empty-widget",
                    --     style = "flib_titlebar_drag_handle",
                    --     ignored_by_interaction = true,
                    -- }
                },
                {
                    type = "frame",
                    direction = "vertical",
                    style = "inside_shallow_frame",

                    {
                        type = "flow",
                        direction = "vertical",
                        style_mods = {
                            padding = 12,
                        },

                        {
                            type = "label",
                            caption =
                            "The train with the specified train ID (if found) will be dispatched to this train stop whenever the value of the selected signal changes.",
                            style_mods = {
                                single_line = false,
                                maximal_width = 200,
                            }
                        },
                    },
                    { type = "line" },
                    {
                        type = "flow",
                        direction = "vertical",
                        style_mods = {
                            padding = 12,
                            top_padding = 6,
                        },

                        {
                            type = "label",
                            style = "heading_2_label",
                            caption = "Input signal",
                        },
                        {
                            type = "flow",
                            style_mods = {
                                vertical_align = "center",
                                top_padding = 12,
                            },

                            {
                                type = "label",
                                style_mods = {
                                    right_padding = 24,
                                },
                                caption = "Train ID",
                            },
                            {
                                type = "choose-elem-button",
                                name = "tctrl_signal_selector",
                                -- Haven't found a way to limit the signal selection to exclude the
                                -- [Everything], [Any] and [Each] signals yet.
                                -- Looks like we'd have to remake the whole selector GUI in that case.
                                elem_type = "signal",
                                signal = this_data.selected_signal
                            },
                        },
                    },
                },
            }
        })

        global.tctrl_guis[e.player_index] = {
            gui = tctrl_gui,
            assoc_data = this_data,
        }
    end
end)

script.on_event(defines.events.on_gui_elem_changed, function(e)
    if e.element.name == "tctrl_signal_selector" then
        -- [Everything], [Any] and [Each] signals are not allowed (they don't make sense).
        if
            e.element.elem_value
            and e.element.elem_value.type == "virtual"
            and (e.element.elem_value.name == "signal-everything"
                or e.element.elem_value.name == "signal-anything"
                or e.element.elem_value.name == "signal-each")
        then
            game.print("Invalid signal selected.", {
                color = { 254, 90, 90 },
                game_state = false,
                sound_path = "utility/cannot_build"
            })

            return
        end

        global.tctrl_guis[e.player_index].assoc_data.selected_signal = e.element.elem_value
    end
end)

script.on_event(defines.events.on_tick, function()
    for tsid, tctrl_data in pairs(global.tctrl_data) do
        -- Is the train stop configured for train control?
        if not tctrl_data.selected_signal then return end

        local train_stop = global.train_stops[tsid]
        if not train_stop.valid then
            global.train_stops[tsid] = nil
            global.tctrl_data[tsid] = nil
            return
        end

        -- Is the train stop connected to a circuit network?
        if not train_stop.get_circuit_network(defines.wire_type.red)
            and not train_stop.get_circuit_network(defines.wire_type.green)
        then
            return
        end

        local signal_value = train_stop.get_merged_signal(tctrl_data.selected_signal)

        -- Has the signal value changed since last tick?
        if signal_value == tctrl_data.previous_signal_value then return end
        tctrl_data.previous_signal_value = signal_value

        -- Is the station connected to a rail segment?
        if not train_stop.connected_rail then return end

        local train = game.get_train_by_id(signal_value)
        if not train then return end

        local schedule = train.schedule
        if not schedule then
            schedule = {
                records = {},
                current = 1 -- Lua is 1-indexed
            }
        end
        table.insert(schedule.records, schedule.current, {
            rail = train_stop.connected_rail,
            rail_direction = train_stop.connected_rail_direction,
            temporary = true,
        })
        table.insert(schedule.records, schedule.current + 1, {
            station = train_stop.backer_name,
            wait_conditions = {
                {
                    type = "inactivity",
                    compare_type = "or",
                    ticks = 300,
                },
                {
                    type = "circuit",
                    compare_type = "or",
                    condition = {
                        comparator = "!=",
                        first_signal = { type = "virtual", name = "signal-check" },
                        constant = 0,
                    },
                }
            },
            temporary = true,
        })
        train.schedule = schedule
        train.manual_mode = false
    end
end)

function on_built(e)
    if e.tags and e.tags.tctrl_selected_signal then
        local tsid = e.created_entity.unit_number
        global.train_stops[tsid] = e.created_entity
        global.tctrl_data[tsid] = { selected_signal = e.tags.tctrl_selected_signal }
    end
end

script.on_event(defines.events.on_built_entity, on_built)
script.on_event(defines.events.on_robot_built_entity, on_built)
script.on_event(defines.events.script_raised_built, on_built)

script.on_event(defines.events.on_player_setup_blueprint, function(e)
    local player = game.players[e.player_index]

    local bp = player.blueprint_to_setup
    if not bp or not bp.valid_for_read then
        bp = player.cursor_stack

        if not bp or not bp.valid_for_read then
            return
        end
    end

    for index, entity in ipairs(bp.get_blueprint_entities()) do
        if entity.name ~= "train-stop" then goto continue end

        local real_entity = e.surface.find_entity(entity.name, entity.position)
        if not real_entity then goto continue end

        local tsid = real_entity.unit_number
        if global.tctrl_data[tsid] then
            bp.set_blueprint_entity_tags(index, {
                tctrl_selected_signal = global.tctrl_data[tsid].selected_signal
            })
        end

        ::continue::
    end
end)

script.on_event(defines.events.on_entity_settings_pasted, function(e)
    if e.source.name == "train-stop"
        and e.destination.name == "train-stop"
    then
        local src_tsid = e.source.unit_number
        local dst_tsid = e.destination.unit_number
        if global.tctrl_data[src_tsid] then
            if not global.train_stops[dst_tsid] then
                global.train_stops[dst_tsid] = e.destination
            end
            if not global.tctrl_data[dst_tsid] then
                global.tctrl_data[dst_tsid] = {}
            end
            global.tctrl_data[dst_tsid].selected_signal = global.tctrl_data[src_tsid].selected_signal
        end
    end
end)

-- Still missing a way to copy settings when pasting a blueprint over existing entities.
