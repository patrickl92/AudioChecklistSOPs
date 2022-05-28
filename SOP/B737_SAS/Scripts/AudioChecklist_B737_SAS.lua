local utils = require "audiochecklist.utils"
local sopRegister = require "audiochecklist.sopregister"
local sopExecutor = require "audiochecklist.sopexecutor"
local standardOperatingProcedure = require "audiochecklist.standardoperatingprocedure"
local checklist = require "audiochecklist.checklist"
local soundChecklistItem = require "audiochecklist.soundchecklistitem"
local automaticChecklistItem = require "audiochecklist.automaticchecklistitem"
local automaticDynamicResponseChecklistItem = require "audiochecklist.automaticdynamicresponsechecklistitem"
local manualChecklistItem = require "audiochecklist.manualchecklistitem"
local manualDynamicResponseChecklistItem = require "audiochecklist.manualdynamicresponsechecklistitem"
local waveFileVoice = require "audiochecklist.wavefilevoice"

-- Create the SOP instance
local sasSOP = standardOperatingProcedure:new("SAS")

-- Add the supported planes
sasSOP:addAirplane("B736")
sasSOP:addAirplane("B737")
sasSOP:addAirplane("B738")
sasSOP:addAirplane("B739")

-- Create the voices
local voicesDirectory = SCRIPT_DIRECTORY .. "AudioChecklists" .. DIRECTORY_SEPARATOR .. "B737_SAS" .. DIRECTORY_SEPARATOR .. "voices" .. DIRECTORY_SEPARATOR
local voiceAndy = waveFileVoice:new("Andy", voicesDirectory .. "Andy" .. DIRECTORY_SEPARATOR .. "challenges", voicesDirectory .. "Andy" .. DIRECTORY_SEPARATOR .. "responses")
local voicePatrick = waveFileVoice:new("Patrick", voicesDirectory .. "Patrick" .. DIRECTORY_SEPARATOR .. "challenges", voicesDirectory .. "Patrick" .. DIRECTORY_SEPARATOR .. "responses")
local voiceLars = waveFileVoice:new("Lars", voicesDirectory .. "Lars" .. DIRECTORY_SEPARATOR .. "challenges", voicesDirectory .. "Lars" .. DIRECTORY_SEPARATOR .. "responses")
local voiceTrine = waveFileVoice:new("Trine", voicesDirectory .. "Trine" .. DIRECTORY_SEPARATOR .. "challenges", voicesDirectory .. "Trine" .. DIRECTORY_SEPARATOR .. "responses")

-- Add the voices
sasSOP:addChallengeVoice(voiceAndy)
sasSOP:addChallengeVoice(voicePatrick)
sasSOP:addChallengeVoice(voiceLars)
sasSOP:addChallengeVoice(voiceTrine)
sasSOP:addResponseVoice(voiceAndy)
sasSOP:addResponseVoice(voicePatrick)
sasSOP:addResponseVoice(voiceLars)
sasSOP:addResponseVoice(voiceTrine)

-- Create the checklists
local preflightChecklist = checklist:new("PREFLIGHT")
local beforeStartChecklistToTheLine = checklist:new("BEFORE START TO THE LINE")
local beforeStartChecklistBelowTheLine = checklist:new("BEFORE START BELOW THE LINE")
local beforeTaxiChecklist = checklist:new("BEFORE TAXI")
local beforeTakeoffChecklist = checklist:new("BEFORE TAKEOFF")
local afterTakeoffChecklist = checklist:new("AFTER TAKEOFF")
local descentChecklist = checklist:new("DESCENT")
local approachChecklist = checklist:new("APPROACH")
local landingChecklist = checklist:new("LANDING")
local shutdownChecklist = checklist:new("SHUTDOWN")
local secureChecklist = checklist:new("SECURE")

-- Add the checklists to the SOP
sasSOP:addChecklist(preflightChecklist)
sasSOP:addChecklist(beforeStartChecklistToTheLine)
sasSOP:addChecklist(beforeStartChecklistBelowTheLine)
sasSOP:addChecklist(beforeTaxiChecklist)
sasSOP:addChecklist(beforeTakeoffChecklist)
sasSOP:addChecklist(afterTakeoffChecklist)
sasSOP:addChecklist(descentChecklist)
sasSOP:addChecklist(approachChecklist)
sasSOP:addChecklist(landingChecklist)
sasSOP:addChecklist(shutdownChecklist)
sasSOP:addChecklist(secureChecklist)

-- Register the SOP instance
sopRegister.addSOP(sasSOP)

-- Define the variables to remember whether the required actions were executed prior to the verification of certain checklist items
local fuelShutoffValveLeftOffChecked = false
local fuelShutoffValveRightOffChecked = false
local fuelShutoffValveLeftChecked = false
local fuelShutoffValveRightChedked = false
local oxygenChecked = false
local recallCheckedBeforeTaxi = false
local recallCheckedForDescent = false
local flightControlYokeFullForwardChecked = false
local flightControlYokeFullBackwardChecked = false
local flightControlYokeFullLeftChecked = false
local flightControlYokeFullRightChecked = false
local flightControlRudderFullRightChecked = false
local flightControlRudderFullLeftChecked = false
local togaActive = false

--- Resets the state of all checklists
local function resetAllChecklists()
	for _, checklist in ipairs(sasSOP:getAllChecklists()) do
		checklist:reset()
	end
end

--- Updates the local variables based on the DataRef values of X-Plane
-- This function is called every second and is used to update values which are not required immediately
local function updateDataRefVariablesOften()
	enginesRunning = utils.checkArrayValuesAllInteger("sim/flightmodel/engine/ENGN_running", 0, 2, function(v) return v == 1 end)

	if utils.readDataRefFloat("laminar/B738/controls/gear_handle_down") == 1 then
		-- Reset the Recall check for the descent if the landing gear is deployed
		recallCheckedForDescent = false
	end

	local togaActivated = false
	if utils.readDataRefFloat("laminar/B738/autopilot/pfd_alt_mode") == 11 then
		-- Aircraft is in TO/GA mode
		if not togaActive then
			togaActive = true
			togaActivated = true
		end
	else
		togaActive = false
	end

	if togaActivated then
		-- Stop the current checklist if TO/GA was activated
		sopExecutor.stopChecklist()

		-- Reset the airborne checklists if TO/GA was activated
		afterTakeoffChecklist:reset()
		descentChecklist:reset()
		approachChecklist:reset()
		landingChecklist:reset()
	end
end

--- Updates the local variables based on the DataRef values of X-Plane
-- Reading DataRef values is a relatively slow operation and should only be done if necessary
-- For this reason all values are checked whether they have been already set to the expected value before reading the according DataRef
-- This function is called for every single frame and is used to update values which are missed otherwise
local function updateDataRefVariablesEveryFrame()
	if not fuelShutoffValveLeftChecked then
		if not fuelShutoffValveLeftOffChecked and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 1 and utils.readDataRefFloat("laminar/B738/annunciator/eng1_valve_closed") == 0 then
			fuelShutoffValveLeftOffChecked = true
		end

		if fuelShutoffValveLeftOffChecked and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 0 and utils.readDataRefFloat("laminar/B738/annunciator/eng1_valve_closed") == 0.5 then
			fuelShutoffValveLeftChecked = true
		end
	end

	if not fuelShutoffValveRightChecked then
		if not fuelShutoffValveRightOffChecked and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 1 and utils.readDataRefFloat("laminar/B738/annunciator/eng2_valve_closed") == 0 then
			fuelShutoffValveRightOffChecked = true
		end

		if fuelShutoffValveRightOffChecked and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 0 and utils.readDataRefFloat("laminar/B738/annunciator/eng2_valve_closed") == 0.5 then
			fuelShutoffValveRightChecked = true
		end
	end

	if not oxygenChecked and (utils.readDataRefFloat("laminar/B738/push_button/oxy_test_cpt_pos") == 1 or utils.readDataRefFloat("laminar/B738/push_button/oxy_test_fo_pos") == 1) then
		-- The oxygon check has been performed
		oxygenChecked = true
	end

	-- Only check certain values if the engines are running, to prevent any decrease in performance
	if enginesRunning then
		if not recallCheckedBeforeTaxi and (utils.readDataRefFloat("laminar/B738/buttons/capt_6_pack_pos") == 1 or utils.readDataRefFloat("laminar/B738/buttons/fo_6_pack_pos") == 1) then
			recallCheckedBeforeTaxi = true
		end

		if not recallCheckedForDescent and (utils.readDataRefFloat("laminar/B738/buttons/capt_6_pack_pos") == 1 or utils.readDataRefFloat("laminar/B738/buttons/fo_6_pack_pos") == 1) and utils.readDataRefFloat("laminar/B738/controls/gear_handle_down", 0) <= 0.5 then
			recallCheckedForDescent = true
		end

		if not flightControlYokeFullForwardChecked and utils.readDataRefFloat("laminar/yoke/pitch", 0) < -0.9 then
			flightControlYokeFullForwardChecked = true
		end

		if not flightControlYokeFullBackwardChecked and utils.readDataRefFloat("laminar/yoke/pitch", 0) > 0.9 then
			flightControlYokeFullBackwardChecked = true
		end

		if not flightControlYokeFullLeftChecked and utils.readDataRefFloat("laminar/yoke/roll", 0) < -0.9 then
			flightControlYokeFullLeftChecked = true
		end

		if not flightControlYokeFullRightChecked and utils.readDataRefFloat("laminar/yoke/roll", 0) > 0.9 then
			flightControlYokeFullRightChecked = true
		end

		if not flightControlRudderFullRightChecked and utils.readDataRefFloat("sim/cockpit2/controls/yoke_heading_ratio", 0) > 0.9 then
			flightControlRudderFullRightChecked = true
		end

		if not flightControlRudderFullLeftChecked and utils.readDataRefFloat("sim/cockpit2/controls/yoke_heading_ratio", 0) < -0.9 then
			flightControlRudderFullLeftChecked = true
		end
	else
		-- Engine has been shut down, reset the values for the next sector
		recallCheckedBeforeTaxi = false
		recallCheckedForDescent = false
		flightControlYokeFullForwardChecked = false
		flightControlYokeFullBackwardChecked = false
		flightControlYokeFullLeftChecked = false
		flightControlYokeFullRightChecked = false
		flightControlRudderFullRightChecked = false
		flightControlRudderFullLeftChecked = false
	end
end

--- Gets the key of the response sound file for the fuel pumps checklist item
-- @treturn string The key of the response sound file to play
local function getResponseFuelPumps()
	if utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr1") == 1 then
		return "FUEL_PUMPS_6_ON"
	end

	return "FUEL_PUMPS_4_ON"
end

--- Gets the key of the response sound file for the anti-ice checklist item
-- @treturn string The key of the response sound file to play
local function getResponseAntiIce()
	if utils.readDataRefFloat("laminar/B738/ice/eng1_heat_pos") == 1 then
		return "ON"
	end

	return "OFF"
end

--- Gets the key of the response sound file for the set flaps checklist item
-- @treturn string The key of the response sound file to play
local function getResponseFlapsSet()
	local flapLeverPos = utils.readDataRefFloat("laminar/B738/flt_ctrls/flap_lever")

	if flapLeverPos == 0.125 then
		return "FLAPS_1_SET"
	end

	if flapLeverPos == 0.375 then
		return "FLAPS_5_SET"
	end

	if flapLeverPos == 0.5 then
		return "FLAPS_10_SET"
	end

	if flapLeverPos == 0.625 then
		return "FLAPS_15_SET"
	end

	if flapLeverPos == 0.875 then
		return "FLAPS_30_SET"
	end

	if flapLeverPos == 1 then
		return "FLAPS_40_SET"
	end

	return "CHECKED"
end

--- Gets the key of the response sound file for the set flaps checklist item
-- @treturn string The key of the response sound file to play
local function getResponseFlapsSetGreenLight()
	local flapLeverPos = utils.readDataRefFloat("laminar/B738/flt_ctrls/flap_lever")

	if flapLeverPos == 0.125 then
		return "FLAPS_1_SET_GREEN_LIGHT"
	end

	if flapLeverPos == 0.375 then
		return "FLAPS_5_SET_GREEN_LIGHT"
	end

	if flapLeverPos == 0.5 then
		return "FLAPS_10_SET_GREEN_LIGHT"
	end

	if flapLeverPos == 0.625 then
		return "FLAPS_15_SET_GREEN_LIGHT"
	end

	if flapLeverPos == 0.875 then
		return "FLAPS_30_SET_GREEN_LIGHT"
	end

	if flapLeverPos == 1 then
		return "FLAPS_40_SET_GREEN_LIGHT"
	end

	return "CHECKED"
end

--- Gets the key of the response sound file for the autobrake checklist item
-- @treturn string The key of the response sound file to play
local function getResponseAutobrake()
	local autobrakeSwitchPosition = utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos")

	if autobrakeSwitchPosition == 1 then
		return "AUTOBRAKE_OFF"
	end

	if autobrakeSwitchPosition == 2 then
		return "AUTOBRAKE_1"
	end

	if autobrakeSwitchPosition == 3 then
		return "AUTOBRAKE_2"
	end

	if autobrakeSwitchPosition == 4 then
		return "AUTOBRAKE_3"
	end

	if autobrakeSwitchPosition == 5 then
		return "AUTOBRAKE_MAX"
	end

	return "CHECKED"
end

--- Gets the key of the response sound file for the altimeter checklist item
-- @treturn string The key of the response sound file to play
local function getResponseAltimeter()
	if utils.readDataRefFloat("laminar/B738/EFIS/baro_set_std_pilot") == 1 then
		return "STANDARD_SET"
	end

	return "QNH_SET"
end

--- Gets the key of the response sound file for the parking brake checklist item
-- @treturn string The key of the response sound file to play
local function getResponseParkingBrake()
	local chocksSet = utils.readDataRefFloat("laminar/B738/fms/chock_status") == 1

	if utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 and chocksSet then
		return "SET_CHOCKS_INSTALLED"
	end

	if chocksSet then
		return "NOT_SET_CHOCKS_INSTALLED"
	end

	return "SET"
end

--- Checks whether the stab trim is set to the calculated stab trim of the FMS
-- @treturn bool True if the stab trim is set correctly, otherwise false
local function evaluateStabTrim()
	local trimCalculated = utils.readDataRefFloat("laminar/B738/FMS/trim_calc")
	local trimWheel = utils.readDataRefFloat("laminar/B738/flt_ctrls/trim_wheel")
	
	if not trimCalculated or not trimWheel then
		return false
	end
	
	return math.abs(trimCalculated - (8 + 8 * trimWheel)) < 1
end

--- Adds the mapping of the challenge sound files to a waveFileVoice.
-- @tparam waveFileVoice voice The voice.
local function addChallengeSoundFilesMapping(voice)
	voice:addChallengeSoundFile("Preflight_Start", "Preflight_Start.wav")
	voice:addChallengeSoundFile("Preflight_FuelShutoffValves", "Preflight_FuelShutoffValves.wav")
	voice:addChallengeSoundFile("Preflight_Oxygen", "Preflight_Oxygen.wav")
	voice:addChallengeSoundFile("Preflight_NavTransferDisplaySwitches", "Preflight_NavTransferDisplaySwitches.wav")
	voice:addChallengeSoundFile("Preflight_WindowHeat", "Preflight_WindowHeat.wav")
	voice:addChallengeSoundFile("Preflight_PressModeSelector", "Preflight_PressModeSelector.wav")
	voice:addChallengeSoundFile("Preflight_FlightInstruments", "Preflight_FlightInstruments.wav")
	voice:addChallengeSoundFile("Preflight_ParkingBrake", "Preflight_ParkingBrake.wav")
	voice:addChallengeSoundFile("Preflight_EngineStartLevers", "Preflight_EngineStartLevers.wav")
	voice:addChallengeSoundFile("Preflight_Complete", "Preflight_Complete.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_Start", "BeforeStartToTheLine_Start.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_Fuel", "BeforeStartToTheLine_Fuel.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_FuelPumps", "BeforeStartToTheLine_FuelPumps.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_PassengerSigns", "BeforeStartToTheLine_PassengerSigns.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_Windows", "BeforeStartToTheLine_Windows.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_MCP", "BeforeStartToTheLine_MCP.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_TakeoffSpeeds", "BeforeStartToTheLine_TakeoffSpeeds.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_CduPreflight", "BeforeStartToTheLine_CduPreflight.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_TaxiTakeoffBriefing", "BeforeStartToTheLine_TaxiTakeoffBriefing.wav")
	voice:addChallengeSoundFile("BeforeStartToTheLine_Complete", "BeforeStartToTheLine_Complete.wav")
	voice:addChallengeSoundFile("BeforeStartBelowTheLine_Start", "BeforeStartBelowTheLine_Start.wav")
	voice:addChallengeSoundFile("BeforeStartBelowTheLine_FlightDeckDoor", "BeforeStartBelowTheLine_FlightDeckDoor.wav")
	voice:addChallengeSoundFile("BeforeStartBelowTheLine_AntiCollisionLight", "BeforeStartBelowTheLine_AntiCollisionLight.wav")
	voice:addChallengeSoundFile("BeforeStartBelowTheLine_Complete", "BeforeStartBelowTheLine_Complete.wav")
	voice:addChallengeSoundFile("BeforeTaxi_Start", "BeforeTaxi_Start.wav")
	voice:addChallengeSoundFile("BeforeTaxi_Generators", "BeforeTaxi_Generators.wav")
	voice:addChallengeSoundFile("BeforeTaxi_ProbeHeat", "BeforeTaxi_ProbeHeat.wav")
	voice:addChallengeSoundFile("BeforeTaxi_AntiIce", "BeforeTaxi_AntiIce.wav")
	voice:addChallengeSoundFile("BeforeTaxi_IsolationValve", "BeforeTaxi_IsolationValve.wav")
	voice:addChallengeSoundFile("BeforeTaxi_EngineStartSwitches", "BeforeTaxi_EngineStartSwitches.wav")
	voice:addChallengeSoundFile("BeforeTaxi_Recall", "BeforeTaxi_Recall.wav")
	voice:addChallengeSoundFile("BeforeTaxi_Autobrake", "BeforeTaxi_Autobrake.wav")
	voice:addChallengeSoundFile("BeforeTaxi_Flaps", "BeforeTaxi_Flaps.wav")
	voice:addChallengeSoundFile("BeforeTaxi_EngineStartLevers", "BeforeTaxi_EngineStartLevers.wav")
	voice:addChallengeSoundFile("BeforeTaxi_RudderAileronTrim", "BeforeTaxi_RudderAileronTrim.wav")
	voice:addChallengeSoundFile("BeforeTaxi_FlightControls", "BeforeTaxi_FlightControls.wav")
	voice:addChallengeSoundFile("BeforeTaxi_GroundEquipment", "BeforeTaxi_GroundEquipment.wav")
	voice:addChallengeSoundFile("BeforeTaxi_Complete", "BeforeTaxi_Complete.wav")
	voice:addChallengeSoundFile("BeforeTakeoff_Start", "BeforeTakeoff_Start.wav")
	voice:addChallengeSoundFile("BeforeTakeoff_CabinReport", "BeforeTakeoff_CabinReport.wav")
	voice:addChallengeSoundFile("BeforeTakeoff_Flaps", "BeforeTakeoff_Flaps.wav")
	voice:addChallengeSoundFile("BeforeTakeoff_StabilizerTrim", "BeforeTakeoff_StabilizerTrim.wav")
	voice:addChallengeSoundFile("BeforeTakeoff_Complete", "BeforeTakeoff_Complete.wav")
	voice:addChallengeSoundFile("AfterTakeoff_Start", "AfterTakeoff_Start.wav")
	voice:addChallengeSoundFile("AfterTakeoff_Altimeter", "AfterTakeoff_Altimeter.wav")
	voice:addChallengeSoundFile("AfterTakeoff_EngineBleeds", "AfterTakeoff_EngineBleeds.wav")
	voice:addChallengeSoundFile("AfterTakeoff_Packs", "AfterTakeoff_Packs.wav")
	voice:addChallengeSoundFile("AfterTakeoff_LandingGear", "AfterTakeoff_LandingGear.wav")
	voice:addChallengeSoundFile("AfterTakeoff_Flaps", "AfterTakeoff_Flaps.wav")
	voice:addChallengeSoundFile("AfterTakeoff_Complete", "AfterTakeoff_Complete.wav")
	voice:addChallengeSoundFile("Descent_Start", "Descent_Start.wav")
	voice:addChallengeSoundFile("Descent_Pressurization", "Descent_Pressurization.wav")
	voice:addChallengeSoundFile("Descent_Recall", "Descent_Recall.wav")
	voice:addChallengeSoundFile("Descent_Autobrake", "Descent_Autobrake.wav")
	voice:addChallengeSoundFile("Descent_LandingData", "Descent_LandingData.wav")
	voice:addChallengeSoundFile("Descent_ApproachBriefing", "Descent_ApproachBriefing.wav")
	voice:addChallengeSoundFile("Descent_Complete", "Descent_Complete.wav")
	voice:addChallengeSoundFile("Approach_Start", "Approach_Start.wav")
	voice:addChallengeSoundFile("Approach_Altimeter", "Approach_Altimeter.wav")
	voice:addChallengeSoundFile("Approach_Complete", "Approach_Complete.wav")
	voice:addChallengeSoundFile("Landing_Start", "Landing_Start.wav")
	voice:addChallengeSoundFile("Landing_CabinReport", "Landing_CabinReport.wav")
	voice:addChallengeSoundFile("Landing_EngineStartSwitches", "Landing_EngineStartSwitches.wav")
	voice:addChallengeSoundFile("Landing_SpeedBrake", "Landing_SpeedBrake.wav")
	voice:addChallengeSoundFile("Landing_LandingGear", "Landing_LandingGear.wav")
	voice:addChallengeSoundFile("Landing_Flaps", "Landing_Flaps.wav")
	voice:addChallengeSoundFile("Landing_Complete", "Landing_Complete.wav")
	voice:addChallengeSoundFile("Shutdown_Start", "Shutdown_Start.wav")
	voice:addChallengeSoundFile("Shutdown_FuelPumps", "Shutdown_FuelPumps.wav")
	voice:addChallengeSoundFile("Shutdown_ProbeHeat", "Shutdown_ProbeHeat.wav")
	voice:addChallengeSoundFile("Shutdown_HydraulicPanel", "Shutdown_HydraulicPanel.wav")
	voice:addChallengeSoundFile("Shutdown_Flaps", "Shutdown_Flaps.wav")
	voice:addChallengeSoundFile("Shutdown_ParkingBrake", "Shutdown_ParkingBrake.wav")
	voice:addChallengeSoundFile("Shutdown_EngineStartLevers", "Shutdown_EngineStartLevers.wav")
	voice:addChallengeSoundFile("Shutdown_WeatherRadar", "Shutdown_WeatherRadar.wav")
	voice:addChallengeSoundFile("Shutdown_AircraftLog", "Shutdown_AircraftLog.wav")
	voice:addChallengeSoundFile("Shutdown_Complete", "Shutdown_Complete.wav")
	voice:addChallengeSoundFile("Secure_Start", "Secure_Start.wav")
	voice:addChallengeSoundFile("Secure_IRS", "Secure_IRS.wav")
	voice:addChallengeSoundFile("Secure_EmergencyExitLights", "Secure_EmergencyExitLights.wav")
	voice:addChallengeSoundFile("Secure_WindowHeat", "Secure_WindowHeat.wav")
	voice:addChallengeSoundFile("Secure_Packs", "Secure_Packs.wav")
	voice:addChallengeSoundFile("Secure_OutflowValve", "Secure_OutflowValve.wav")
	voice:addChallengeSoundFile("Secure_Electrical", "Secure_Electrical.wav")
	voice:addChallengeSoundFile("Secure_ApuGrdPowerSwitch", "Secure_ApuGrdPowerSwitch.wav")
	voice:addChallengeSoundFile("Secure_BatterySwitch", "Secure_BatterySwitch.wav")
	voice:addChallengeSoundFile("Secure_Complete", "Secure_Complete.wav")
end

--- Adds the mapping of the challenge sound files to a waveFileVoice.
-- @tparam waveFileVoice voice The voice.
local function addResponseSoundFilesMapping(voice)
	voice:addResponseSoundFile("CHECKED", "Response_Checked.wav")
	voice:addResponseSoundFile("TESTED, 100%", "Response_Tested100Percent.wav")
	voice:addResponseSoundFile("NORMAL, AUTO", "Response_NormalAuto.wav")
	voice:addResponseSoundFile("ON", "Response_On.wav")
	voice:addResponseSoundFile("OFF", "Response_Off.wav")
	voice:addResponseSoundFile("AUTO", "Response_Auto.wav")
	voice:addResponseSoundFile("SET", "Response_Set.wav")
	voice:addResponseSoundFile("CUTOFF", "Response_CutOff.wav")
	voice:addResponseSoundFile("FUEL_UPLIFT_CHECKED", "Response_FuelUpliftChecked.wav")
	voice:addResponseSoundFile("FUEL_PUMPS_4_ON", "Response_Fuel4PumpsOn.wav")
	voice:addResponseSoundFile("FUEL_PUMPS_6_ON", "Response_Fuel6PumpsOn.wav")
	voice:addResponseSoundFile("CONT", "Response_Cont.wav")
	voice:addResponseSoundFile("V2_HEADING_ALTITUDE_CHECKED_SET", "Response_V2HeadingAltitudeCheckedSet.wav")
	voice:addResponseSoundFile("LOCKED", "Response_Locked.wav")
	voice:addResponseSoundFile("COMPLETED", "Response_Completed.wav")
	voice:addResponseSoundFile("CLOSED AND LOCKED", "Response_ClosedLocked.wav")
	voice:addResponseSoundFile("RTO", "Response_RTO.wav")
	voice:addResponseSoundFile("FLAPS_1_SET", "Response_Flaps1Set.wav")
	voice:addResponseSoundFile("FLAPS_5_SET", "Response_Flaps5Set.wav")
	voice:addResponseSoundFile("FLAPS_10_SET", "Response_Flaps10Set.wav")
	voice:addResponseSoundFile("FLAPS_15_SET", "Response_Flaps15Set.wav")
	voice:addResponseSoundFile("FLAPS_30_SET", "Response_Flaps30Set.wav")
	voice:addResponseSoundFile("FLAPS_40_SET", "Response_Flaps40Set.wav")
	voice:addResponseSoundFile("FLAPS_1_SET_GREEN_LIGHT", "Response_Flaps1SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_5_SET_GREEN_LIGHT", "Response_Flaps5SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_10_SET_GREEN_LIGHT", "Response_Flaps10SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_15_SET_GREEN_LIGHT", "Response_Flaps15SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_30_SET_GREEN_LIGHT", "Response_Flaps30SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_40_SET_GREEN_LIGHT", "Response_Flaps40SetGreenLight.wav")
	voice:addResponseSoundFile("CHECKED_SET_FOR_TAKEOFF", "Response_CheckedSetForTakeoff.wav")
	voice:addResponseSoundFile("QNH_SET", "Response_QNHSet.wav")
	voice:addResponseSoundFile("STANDARD_SET", "Response_StandardSet.wav")
	voice:addResponseSoundFile("IDLE DETENT", "Response_IdleDetent.wav")
	voice:addResponseSoundFile("FREE & ZERO", "Response_FreeZero.wav")
	voice:addResponseSoundFile("CLEAR", "Response_Clear.wav")
	voice:addResponseSoundFile("RECEIVED", "Response_Received.wav")
	voice:addResponseSoundFile("UP NO LIGHT", "Response_UpNoLights.wav")
	voice:addResponseSoundFile("AUTOBRAKE_OFF", "Response_AutobrakeOffSet.wav")
	voice:addResponseSoundFile("AUTOBRAKE_1", "Response_Autobrake1Set.wav")
	voice:addResponseSoundFile("AUTOBRAKE_2", "Response_Autobrake2Set.wav")
	voice:addResponseSoundFile("AUTOBRAKE_3", "Response_Autobrake3Set.wav")
	voice:addResponseSoundFile("AUTOBRAKE_MAX", "Response_AutobrakeMaxSet.wav")
	voice:addResponseSoundFile("VREF_MINIMUMS_CHECKED_SET", "Response_VrefMinimumsCheckedSet.wav")
	voice:addResponseSoundFile("ARMED", "Response_Armed.wav")
	voice:addResponseSoundFile("DOWN", "Response_Down.wav")
	voice:addResponseSoundFile("UP AND OFF", "Response_UpOff.wav")
	voice:addResponseSoundFile("UP", "Response_Up.wav")
	voice:addResponseSoundFile("SET_CHOCKS_INSTALLED", "Response_SetChocksInstalled.wav")
	voice:addResponseSoundFile("NOT_SET_CHOCKS_INSTALLED", "Response_NotSetChocksInstalled.wav")
	voice:addResponseSoundFile("SIGNED/STORED", "Response_SignedStored.wav")
	voice:addResponseSoundFile("POWER DOWN", "Response_PowerDown.wav")
end

-- Set the callbacks for the updates
sasSOP:addDoOftenCallback(updateDataRefVariablesOften)
sasSOP:addDoEveryFrameCallback(updateDataRefVariablesEveryFrame)

-- Reset all checklists for a turnaround
preflightChecklist:addStartedCallback(function() if shutdownChecklist:getState() == checklist.stateCompleted then resetAllChecklists() end end)

-- Add the mappings of the challenge sound
addChallengeSoundFilesMapping(voiceAndy)
addChallengeSoundFilesMapping(voicePatrick)
addChallengeSoundFilesMapping(voiceLars)
addChallengeSoundFilesMapping(voiceTrine)

-- Add the mappings of the response sound
addResponseSoundFilesMapping(voiceAndy)
addResponseSoundFilesMapping(voicePatrick)
addResponseSoundFilesMapping(voiceLars)
addResponseSoundFilesMapping(voiceTrine)

-- Add the available fail sound files
-- Each time a checklist item does not meet its condition, a random fail sound is selected and played
-- Each voice can have its own fail sound files
voiceAndy:addFailSoundFile("Fail_CheckAgain.wav")
voiceAndy:addFailSoundFile("Fail_Damn.wav")
voiceAndy:addFailSoundFile("Fail_Hmm.wav")
voiceAndy:addFailSoundFile("Fail_LetsSee.wav")
voiceAndy:addFailSoundFile("Fail_No.wav")
voiceAndy:addFailSoundFile("Fail_NotAgain.wav")
voiceAndy:addFailSoundFile("Fail_Really.wav")
voiceAndy:addFailSoundFile("Fail_Whoops.wav")
voiceAndy:addFailSoundFile("Fail_YouSure.wav")

voicePatrick:addFailSoundFile("Fail_Damn.wav")
voicePatrick:addFailSoundFile("Fail_Hmm.wav")
voicePatrick:addFailSoundFile("Fail_AhThis.wav")
voicePatrick:addFailSoundFile("Fail_NotAgain.wav")
voicePatrick:addFailSoundFile("Fail_LetsSee.wav")

-- TODO: Add you fail sound files here
voiceLars:addFailSoundFile("Fail_AreYouSure.wav")
voiceLars:addFailSoundFile("Fail_CheckAgain.wav")
voiceLars:addFailSoundFile("Fail_No.wav")
voiceLars:addFailSoundFile("Fail_Really.wav")
voiceLars:addFailSoundFile("Fail_YouSure.wav")

voiceTrine:addFailSoundFile("Fail_IDontThinkSo.wav")
voiceTrine:addFailSoundFile("Fail_YouSureAboutThat.wav")
voiceTrine:addFailSoundFile("Fail_YouWannaCheckThatAgain.wav")

-- ################# PREFLIGHT
preflightChecklist:addItem(soundChecklistItem:new("Preflight_Start"))
preflightChecklist:addItem(automaticChecklistItem:new("FUEL SHUTOFF VALVES", "CHECKED", "Preflight_FuelShutoffValves", function() return fuelShutoffValveLeftChecked and fuelShutoffValveRightChecked end))
preflightChecklist:addItem(automaticChecklistItem:new("OXYGEN", "TESTED, 100%", "Preflight_Oxygen", function() return oxygenChecked end))
preflightChecklist:addItem(automaticChecklistItem:new("NAV TRANSFER & DISPLAY SWITCHES", "NORMAL, AUTO", "Preflight_NavTransferDisplaySwitches", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/vhf_nav_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/irs_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/fmc_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/dspl_ctrl_pnl") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/dspl_source") == 0 end))
preflightChecklist:addItem(automaticChecklistItem:new("WINDOW HEAT", "ON", "Preflight_WindowHeat", function() return utils.readDataRefFloat("laminar/B738/ice/window_heat_l_fwd_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_l_side_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_fwd_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_side_pos") == 1 end))
preflightChecklist:addItem(automaticChecklistItem:new("PRESSURIZATION MODE SELECTOR", "AUTO", "Preflight_PressModeSelector", function() return utils.readDataRefFloat("laminar/B738/pressurization_mode") == 1 end))
preflightChecklist:addItem(manualDynamicResponseChecklistItem:new("FLIGHT INSTRUMENTS", "HEADING __, ALTIMETER __", "Preflight_FlightInstruments", function() return "CHECKED" end))
preflightChecklist:addItem(automaticChecklistItem:new("PARKING BRAKE", "SET", "Preflight_ParkingBrake", function() return utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 end))
preflightChecklist:addItem(automaticChecklistItem:new("ENGINE START LEVERS", "CUTOFF", "Preflight_EngineStartLevers", function() return utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 0 and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 0 end))
preflightChecklist:addItem(soundChecklistItem:new("Preflight_Complete"))

-- ################# BEFORE START TO THE LINE
beforeStartChecklistToTheLine:addItem(soundChecklistItem:new("BeforeStartToTheLine_Start"))
beforeStartChecklistToTheLine:addItem(manualDynamicResponseChecklistItem:new("FUEL", "__ KGS", "BeforeStartToTheLine_Fuel", function() return "FUEL_UPLIFT_CHECKED" end))
beforeStartChecklistToTheLine:addItem(automaticDynamicResponseChecklistItem:new("FUEL PUMPS", "ON", "BeforeStartToTheLine_FuelPumps", getResponseFuelPumps, function() return utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft1") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft2") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt1") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt2") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr1") == utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr2") end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("PASSENGER SIGNS", "ON", "BeforeStartToTheLine_PassengerSigns", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/seatbelt_sign_pos") == 2 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("WINDOWS", "LOCKED", "BeforeStartToTheLine_Windows", function() return true end))
beforeStartChecklistToTheLine:addItem(manualDynamicResponseChecklistItem:new("MCP", "V2 __, HEADING __, ALTITUDE __", "BeforeStartToTheLine_MCP", function() return "V2_HEADING_ALTITUDE_CHECKED_SET" end))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("TAKEOFF SPEEDS", "SET", "BeforeStartToTheLine_TakeoffSpeeds"))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("CDU PREFLIGHT", "COMPLETED", "BeforeStartToTheLine_CduPreflight"))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("TAXI AND TAKEOFF BRIEFING", "COMPLETED", "BeforeStartToTheLine_TaxiTakeoffBriefing"))
beforeStartChecklistToTheLine:addItem(soundChecklistItem:new("BeforeStartToTheLine_Complete"))

-- ################# BEFORE START BELOW THE LINE
beforeStartChecklistBelowTheLine:addItem(soundChecklistItem:new("BeforeStartBelowTheLine_Start"))
beforeStartChecklistBelowTheLine:addItem(automaticChecklistItem:new("FLIGHT DECK DOOR", "CLOSED AND LOCKED", "BeforeStartBelowTheLine_FlightDeckDoor", function() return utils.readDataRefFloat("laminar/B738/door/flt_dk_door_ratio") == 0 end))
beforeStartChecklistBelowTheLine:addItem(automaticChecklistItem:new("ANTI COLLISION LIGHT", "ON", "BeforeStartBelowTheLine_AntiCollisionLight", function() return utils.readDataRefInteger("sim/cockpit2/switches/beacon_on") == 1 end))
beforeStartChecklistBelowTheLine:addItem(soundChecklistItem:new("BeforeStartBelowTheLine_Complete"))

-- ################# BEFORE TAXI
beforeTaxiChecklist:addItem(soundChecklistItem:new("BeforeTaxi_Start"))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("GENERATORS", "ON", "BeforeTaxi_Generators", function() return utils.checkArrayValuesAllInteger("sim/cockpit/electrical/generator_on", 0, 2, function(v) return v == 1 end) end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("PROBE HEAT", "ON", "BeforeTaxi_ProbeHeat", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/capt_probes_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/fo_probes_pos") == 1 end))
beforeTaxiChecklist:addItem(automaticDynamicResponseChecklistItem:new("ANTI-ICE", "__", "BeforeTaxi_AntiIce", getResponseAntiIce, function() return utils.readDataRefFloat("laminar/B738/ice/eng1_heat_pos") == utils.readDataRefFloat("laminar/B738/ice/eng2_heat_pos") end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("ISOLATION VALVE", "AUTO", "BeforeTaxi_IsolationValve", function() return utils.readDataRefFloat("laminar/B738/air/isolation_valve_pos") == 1 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("ENGINE START SWITCHES", "CONT", "BeforeTaxi_EngineStartSwitches", function() return utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 2 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 2 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("RECALL", "CHECKED", "BeforeTaxi_Recall", function() return recallCheckedBeforeTaxi end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("AUTOBRAKE", "RTO", "BeforeTaxi_Autobrake", function() return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos") == 0 end))
beforeTaxiChecklist:addItem(automaticDynamicResponseChecklistItem:new("FLAPS", "__", "BeforeTaxi_Flaps", getResponseFlapsSet, function() return utils.readDataRefFloat("laminar/B738/flt_ctrls/flap_lever", 0) > 0 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("ENGINE START LEVERS", "IDLE DETENT", "BeforeTaxi_EngineStartLevers", function() return utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 1 and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 1 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("RUDDER AND AILERON TRIM", "FREE & ZERO", "BeforeTaxi_RudderAileronTrim", function() return math.abs(utils.readDataRefFloat("sim/cockpit2/controls/rudder_trim", 0)) < 0.01 and math.abs(utils.readDataRefFloat("sim/cockpit2/controls/aileron_trim", 0)) < 0.1 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("FLIGHT CONTROLS", "CHECKED", "BeforeTaxi_FlightControls", function() return flightControlYokeFullForwardChecked and flightControlYokeFullBackwardChecked and flightControlYokeFullLeftChecked and flightControlYokeFullRightChecked and flightControlRudderFullRightChecked and flightControlRudderFullLeftChecked end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("GROUND EQUIPMENT", "CLEAR", "BeforeTaxi_GroundEquipment", function() return true end))
beforeTaxiChecklist:addItem(soundChecklistItem:new("BeforeTaxi_Complete"))

-- ################# BEFORE TAKEOFF
beforeTakeoffChecklist:addItem(soundChecklistItem:new("BeforeTakeoff_Start"))
beforeTakeoffChecklist:addItem(automaticChecklistItem:new("CABIN REPORT", "RECEIVED", "BeforeTakeoff_CabinReport", function() return true end))
beforeTakeoffChecklist:addItem(automaticDynamicResponseChecklistItem:new("FLAPS", "__, GREEN LIGHT", "BeforeTakeoff_Flaps", getResponseFlapsSetGreenLight, function() return utils.readDataRefFloat("laminar/B738/FMS/takeoff_flaps_set") == 1 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") == 1 end))
beforeTakeoffChecklist:addItem(automaticDynamicResponseChecklistItem:new("STABILIZER TRIM", "__, UNITS", "BeforeTakeoff_StabilizerTrim", function() return "CHECKED_SET_FOR_TAKEOFF" end, evaluateStabTrim))
beforeTakeoffChecklist:addItem(soundChecklistItem:new("BeforeTakeoff_Complete"))

-- ################# AFTER TAKEOFF
afterTakeoffChecklist:addItem(soundChecklistItem:new("AfterTakeoff_Start"))
afterTakeoffChecklist:addItem(manualDynamicResponseChecklistItem:new("ALTIMETER", "SET", "AfterTakeoff_Altimeter", getResponseAltimeter))
afterTakeoffChecklist:addItem(automaticChecklistItem:new("ENGINE BLEEDS", "ON", "AfterTakeoff_EngineBleeds", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_1_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_2_pos") == 1 end))
afterTakeoffChecklist:addItem(automaticChecklistItem:new("PACKS", "AUTO", "AfterTakeoff_Packs", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 1 end))
afterTakeoffChecklist:addItem(automaticChecklistItem:new("LANDING GEAR", "UP AND OFF", "AfterTakeoff_LandingGear", function() return utils.readDataRefFloat("laminar/B738/controls/gear_handle_down") == 0.5 end))
afterTakeoffChecklist:addItem(automaticChecklistItem:new("FLAPS", "UP NO LIGHT", "AfterTakeoff_Flaps", function() return utils.checkArrayValuesAllFloat("laminar/B738/flap_indicator", 0, 2, function(v) return v == 0 end) and utils.readDataRefFloat("laminar/B738/annunciator/slats_transit") == 0 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") == 0 end))
afterTakeoffChecklist:addItem(soundChecklistItem:new("AfterTakeoff_Complete"))

-- ################# DESCENT
descentChecklist:addItem(soundChecklistItem:new("Descent_Start"))
descentChecklist:addItem(manualDynamicResponseChecklistItem:new("PRESSURIZATION", "LAND ALT __", "Descent_Pressurization", function() return "SET" end))
descentChecklist:addItem(automaticChecklistItem:new("RECALL", "CHECKED", "Descent_Recall", function() return recallCheckedForDescent end))
descentChecklist:addItem(automaticDynamicResponseChecklistItem:new("AUTOBRAKE", "__", "Descent_Autobrake", getResponseAutobrake, function() return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos", 0) >= 1 end))
descentChecklist:addItem(manualDynamicResponseChecklistItem:new("LANDING DATA", "VREF __, MINIMUMS __", "Descent_LandingData", function() return "VREF_MINIMUMS_CHECKED_SET" end))
descentChecklist:addItem(manualChecklistItem:new("APPROACH BRIEFING", "COMPLETED", "Descent_ApproachBriefing"))
descentChecklist:addItem(soundChecklistItem:new("Descent_Complete"))

-- ################# APPROACH
approachChecklist:addItem(soundChecklistItem:new("Approach_Start"))
approachChecklist:addItem(manualChecklistItem:new("ALTIMETER", "SET", "Approach_Altimeter"))
approachChecklist:addItem(soundChecklistItem:new("Approach_Complete"))

-- ################# LANDING
landingChecklist:addItem(soundChecklistItem:new("Landing_Start"))
landingChecklist:addItem(automaticChecklistItem:new("CABIN REPORT", "RECEIVED", "Landing_CabinReport", function() return true end))
landingChecklist:addItem(automaticChecklistItem:new("ENGINE START SWITCHES", "CONT", "Landing_EngineStartSwitches", function() return utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 2 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 2 end))
landingChecklist:addItem(automaticChecklistItem:new("SPEEDBRAKE", "ARMED", "Landing_SpeedBrake", function() return utils.readDataRefFloat("laminar/B738/annunciator/speedbrake_armed") == 1 and utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever") < 0.1 end))
landingChecklist:addItem(automaticChecklistItem:new("LANDING GEAR", "DOWN", "Landing_LandingGear", function() return utils.readDataRefFloat("laminar/B738/controls/gear_handle_down") == 1 end))
landingChecklist:addItem(automaticDynamicResponseChecklistItem:new("FLAPS", "__, GREEN LIGHT", "Landing_Flaps", getResponseFlapsSetGreenLight, function() return utils.readDataRefFloat("laminar/B738/FMS/approach_flaps_set") == 1 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") == 1 end))
landingChecklist:addItem(soundChecklistItem:new("Landing_Complete"))

-- ################# SHUTDOWN
shutdownChecklist:addItem(soundChecklistItem:new("Shutdown_Start"))
shutdownChecklist:addItem(automaticChecklistItem:new("FUEL PUMPS", "OFF", "Shutdown_FuelPumps", function() return utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft1") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft2") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt1") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt2") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr1") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr2") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("PROBE HEAT", "OFF", "Shutdown_ProbeHeat", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/capt_probes_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/fo_probes_pos") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("HYDRAULIC PANEL", "SET", "Shutdown_HydraulicPanel", function() return true end))
shutdownChecklist:addItem(automaticChecklistItem:new("FLAPS", "UP", "Shutdown_Flaps", function() return utils.checkArrayValuesAllFloat("laminar/B738/flap_indicator", 0, 2, function(v) return v == 0 end) and utils.readDataRefFloat("laminar/B738/annunciator/slats_transit") == 0 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") == 0 end))
shutdownChecklist:addItem(automaticDynamicResponseChecklistItem:new("PARKING BRAKE", "SET", "Shutdown_ParkingBrake", getResponseParkingBrake, function() return utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 or utils.readDataRefFloat("laminar/B738/fms/chock_status") == 1 end))
shutdownChecklist:addItem(automaticChecklistItem:new("ENGINE START LEVERS", "CUTOFF", "Shutdown_EngineStartLevers", function() return utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 0 and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("WEATHER RADAR", "OFF", "Shutdown_WeatherRadar", function() return utils.readDataRefInteger("sim/cockpit2/EFIS/EFIS_weather_on") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("AIRCRAFT LOG / NOTOC", "SIGNED/STORED", "Shutdown_AircraftLog", function() return true end))
shutdownChecklist:addItem(soundChecklistItem:new("Shutdown_Complete"))

-- ################# SECURE
secureChecklist:addItem(soundChecklistItem:new("Secure_Start"))
secureChecklist:addItem(automaticChecklistItem:new("IRSs", "OFF", "Secure_IRS", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/irs_left") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/irs_right") == 0 end))
secureChecklist:addItem(automaticChecklistItem:new("EMERGENCY EXIT LIGHTS", "OFF", "Secure_EmergencyExitLights", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/emer_exit_lights") == 0 end))
secureChecklist:addItem(automaticChecklistItem:new("WINDOW HEAT", "OFF", "Secure_WindowHeat", function() return utils.readDataRefFloat("laminar/B738/ice/window_heat_l_fwd_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/window_heat_l_side_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_fwd_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_side_pos") == 0 end))
secureChecklist:addItem(automaticChecklistItem:new("PACKS", "OFF", "Secure_Packs", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 0 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 0 end))
secureChecklist:addItem(automaticDynamicResponseChecklistItem:new("OUTFLOW VALVE", "AS REQUIRED", "Secure_OutflowValve", function() return "SET" end, function() return true end))
secureChecklist:addItem(automaticChecklistItem:new("ELECTRICAL", "POWER DOWN", "Secure_Electrical", function() return true end))
secureChecklist:addItem(automaticChecklistItem:new("APU AND GRD POWER SWITCH", "OFF", "Secure_ApuGrdPowerSwitch", function() return utils.readDataRefFloat("laminar/B738/spring_toggle_switch/APU_start_pos") == 0 and utils.readDataRefFloat("laminar/B738/electric/dc_gnd_service") == 0 end))
secureChecklist:addItem(automaticChecklistItem:new("BATTERY SWITCH", "OFF", "Secure_BatterySwitch", function() return utils.readDataRefFloat("laminar/B738/electric/battery_pos") == 0 end))
secureChecklist:addItem(soundChecklistItem:new("Secure_Complete"))