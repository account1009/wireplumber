-- WirePlumber
--
-- Copyright © 2022 Collabora Ltd.
-- Copyright © 2025 Richard Acayan
--
-- SPDX-License-Identifier: MIT
--
-- Find the best Voice Call profile for a device if there is an active call
-- (adapted from device/find-best-profile.lua)

cutils = require ("common-utils")
log = Log.open_topic ("s-device")
started = false

alsa_devs_om = ObjectManager {
  Interest {
    type = "device",
    Constraint { "device.api", "=", "alsa" },
  }
}

mm = Plugin.find ("modem-manager")
mm:connect ("voice-call-start", function ()
  started = true
  source = source or Plugin.find ("standard-event-source")

  for device in alsa_devs_om:iterate () do
    event = source:call ("push-event", "select-profile", device, nil)
  end
end)

mm:connect ("voice-call-stop", function ()
  started = false
  source = source or Plugin.find ("standard-event-source")

  for device in alsa_devs_om:iterate () do
    event = source:call ("push-event", "select-profile", device, nil)
  end
end)

SimpleEventHook {
  name = "device/find-calling-profile",
  before = "device/find-stored-profile",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-profile" },
    },
  },
  execute = function (event)
    local selected_profile = event:get_data ("selected-profile")
    if selected_profile then
      return
    end

    local profile_prefix = "^Voice Call"

    local device = event:get_subject ()
    local dev_name = device.properties["device.name"] or ""

    for p in device:iterate_params ("EnumProfile") do
      local profile = cutils.parseParam (p, "EnumProfile")
      log:debug (device, string.format (
          "Checking profile '%s': available == %s, priority == %d",
          profile.name, profile.available, profile.priority))
      local compatible
      if started then
        compatible = string.find (profile.name, profile_prefix) ~= nil
      else
        compatible = string.find (profile.name, profile_prefix) == nil
      end

      if profile.available ~= "no" and compatible then
        if (not selected_profile) or selected_profile.priority < profile.priority then
          selected_profile = profile
        end
      end
    end

    if selected_profile then
      local type_name
      if started then
        type_name = "calling start"
      else
        type_name = "calling end"
      end
      log:info (device, string.format (
          "Found %s profile '%s' (%d) for device %s",
          type_name, selected_profile.name, selected_profile.index, dev_name))
      event:set_data ("selected-profile", selected_profile)
    end
  end
}:register ()

alsa_devs_om:activate ()
