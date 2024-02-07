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

-- The Level Up 737 variants do not provide the Voice Recorder switch
local isLevelUpAircraft = false
if string.find(AIRCRAFT_FILENAME, "737_[6-9][0E]NG%.acf") then
	-- known aircraft file names:
	-- 737_60NG.acf
	-- 737_70NG.acf
	-- 737_80NG.acf
	-- 737_90NG.acf
	-- 737_9ENG.acf
	isLevelUpAircraft = true
end

-- Create the SOP instance
local ziboDefaultSOP = standardOperatingProcedure:new("Zibo Default")

-- Add the supported planes
ziboDefaultSOP:addAirplane("B736")
ziboDefaultSOP:addAirplane("B737")
ziboDefaultSOP:addAirplane("B738")
ziboDefaultSOP:addAirplane("B739")

-- Create the voices
local voicesDirectory = SCRIPT_DIRECTORY .. "AudioChecklists" .. DIRECTORY_SEPARATOR .. "B737_ZiboDefault" .. DIRECTORY_SEPARATOR .. "voices" .. DIRECTORY_SEPARATOR
local voiceAndy = waveFileVoice:new("Andy", voicesDirectory .. "Andy" .. DIRECTORY_SEPARATOR .. "challenges", voicesDirectory .. "Andy" .. DIRECTORY_SEPARATOR .. "responses")
local voicePatrick = waveFileVoice:new("Patrick", nil, voicesDirectory .. "Patrick" .. DIRECTORY_SEPARATOR .. "responses")
local voiceLars = waveFileVoice:new("Lars", voicesDirectory .. "Lars" .. DIRECTORY_SEPARATOR .. "challenges", voicesDirectory .. "Lars" .. DIRECTORY_SEPARATOR .. "responses")
local voiceFlightdeck2Sim = waveFileVoice:new("flightdeck2sim", voicesDirectory .. "flightdeck2sim" .. DIRECTORY_SEPARATOR .. "challenges", voicesDirectory .. "flightdeck2sim" .. DIRECTORY_SEPARATOR .. "responses")

-- Add the voices
ziboDefaultSOP:addChallengeVoice(voiceAndy)
ziboDefaultSOP:addChallengeVoice(voiceLars)
ziboDefaultSOP:addChallengeVoice(voiceFlightdeck2Sim)
ziboDefaultSOP:addResponseVoice(voiceAndy)
ziboDefaultSOP:addResponseVoice(voicePatrick)
ziboDefaultSOP:addResponseVoice(voiceLars)
ziboDefaultSOP:addResponseVoice(voiceFlightdeck2Sim)

-- Create the checklists
local safetyInspectionChecklist = checklist:new("SAFETY INSPECTION")
local beforeStartChecklistToTheLine = checklist:new("BEFORE START TO THE LINE")
local beforeStartChecklistToTheLineTransit = checklist:new("BEFORE START TO THE LINE (TRANSIT)")
local beforeStartChecklistBelowTheLine = checklist:new("BEFORE START BELOW THE LINE")
local beforeTaxiChecklist = checklist:new("BEFORE TAXI")
local beforeTakeoffChecklistToTheLine = checklist:new("BEFORE TAKEOFF TO THE LINE")
local beforeTakeoffChecklistBelowTheLine = checklist:new("BEFORE TAKEOFF BELOW THE LINE")
local afterTakeoffChecklist = checklist:new("AFTER TAKEOFF")
local descentChecklist = checklist:new("DESCENT")
local approachChecklist = checklist:new("APPROACH")
local landingChecklist = checklist:new("LANDING")
local shutdownChecklist = checklist:new("SHUTDOWN")
local shutdownChecklistTransit = checklist:new("SHUTDOWN (TRANSIT)")
local secureChecklist = checklist:new("SECURE")

-- Add the checklists to the SOP
ziboDefaultSOP:addChecklist(safetyInspectionChecklist)
ziboDefaultSOP:addChecklist(beforeStartChecklistToTheLine)
ziboDefaultSOP:addChecklist(beforeStartChecklistToTheLineTransit)
ziboDefaultSOP:addChecklist(beforeStartChecklistBelowTheLine)
ziboDefaultSOP:addChecklist(beforeTaxiChecklist)
ziboDefaultSOP:addChecklist(beforeTakeoffChecklistToTheLine)
ziboDefaultSOP:addChecklist(beforeTakeoffChecklistBelowTheLine)
ziboDefaultSOP:addChecklist(afterTakeoffChecklist)
ziboDefaultSOP:addChecklist(descentChecklist)
ziboDefaultSOP:addChecklist(approachChecklist)
ziboDefaultSOP:addChecklist(landingChecklist)
ziboDefaultSOP:addChecklist(shutdownChecklist)
ziboDefaultSOP:addChecklist(shutdownChecklistTransit)
ziboDefaultSOP:addChecklist(secureChecklist)

-- Register the SOP instance
sopRegister.addSOP(ziboDefaultSOP)

-- Define the variables to remember whether the required actions were executed prior to the verification of certain checklist items
local lightTestDone = false
local oxygenChecked = false
local fireWarningTestDone = false
local enginesRunning = false
local radioAltimeterActive = false
local flightControlYokeFullForwardChecked = false
local flightControlYokeFullBackwardChecked = false
local flightControlYokeFullLeftChecked = false
local flightControlYokeFullRightChecked = false
local flightControlRudderFullRightChecked = false
local flightControlRudderFullLeftChecked = false
local recallCheckedBeforeTaxi = false
local recallCheckedLanding = false
local takeoffConfigChecked = false
local togaActive = false
local isMissedApproach = false

--- Resets the state of all checklists, except the given one
-- @tparam ?checklist checklistToIgnore If specified, this checklist is not reset
local function resetAllChecklistsExcept(checklistToIgnore)
	for _, checklist in ipairs(ziboDefaultSOP:getAllChecklists()) do
		if checklist ~= checklistToIgnore then
			checklist:reset()
		end
	end
end

--- Updates the local variables based on the DataRef values of X-Plane
-- This function is called every second and is used to update values which are not required immediately
local function updateDataRefVariablesOften()
	enginesRunning = utils.checkArrayValuesAllInteger("sim/flightmodel/engine/ENGN_running", 0, 2, function(v) return v == 1 end)

	local radioAltimeterValue = utils.readDataRefFloat("sim/cockpit2/gauges/indicators/radio_altimeter_height_ft_pilot", 0)
	radioAltimeterActive = radioAltimeterValue > 1 and radioAltimeterValue <= 2500

	if radioAltimeterValue <= 1 then
		-- Aircraft is on the ground
		isMissedApproach = false
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

		-- Reset the values for the next approach in case of a go around
		recallCheckedLanding = false

		if radioAltimeterValue > 1 then
			-- Indicate a missed approach if the airplane was not on the ground when TO/GA was activated
			isMissedApproach = true
		end
	end
end

--- Updates the local variables based on the DataRef values of X-Plane
-- Reading DataRef values is a relatively slow operation and should only be done if necessary
-- For this reason all values are checked whether they have been already set to the expected value before reading the according DataRef
-- This function is called for every single frame and is used to update values which are missed otherwise
local function updateDataRefVariablesEveryFrame()
	if not lightTestDone and utils.readDataRefFloat("laminar/B738/toggle_switch/bright_test") == 1 then
		-- The light test has been performed
		lightTestDone = true
	end

	if not oxygenChecked and (utils.readDataRefFloat("laminar/B738/push_button/oxy_test_cpt_pos") == 1 or utils.readDataRefFloat("laminar/B738/push_button/oxy_test_fo_pos") == 1) then
		-- The oxygon check has been performed
		oxygenChecked = true
	end

	if not fireWarningTestDone
		--X-Plane 12 appears to have changed the value that annunciators return when lit so that they are no longer 0 or 1
		--but a range between 0 and 1
		and utils.readDataRefFloat("laminar/B738/toggle_switch/fire_test") == 1
		and utils.readDataRefFloat("laminar/B738/annunciator/fire_bell_annun") > 0.0
		and utils.readDataRefFloat("laminar/B738/annunciator/fire_bell_annun2") > 0.0
		and utils.readDataRefFloat("laminar/B738/annunciator/wheel_well_fire") > 0.0
		and utils.readDataRefFloat("laminar/B738/annunciator/engine1_fire") > 0.0
		and utils.readDataRefFloat("laminar/B738/annunciator/engine1_ovht") > 0.0
		and utils.readDataRefFloat("laminar/B738/annunciator/engine2_fire") > 0.0
		and utils.readDataRefFloat("laminar/B738/annunciator/engine2_ovht") > 0.0
		and utils.readDataRefFloat("laminar/B738/annunciator/apu_fire") > 0.0
		then
		-- The fire warning test has been performed
		fireWarningTestDone = true
	end

	-- Only check certain values if the engines are running, to prevent any decrease in performance
	if enginesRunning then
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

		if not recallCheckedBeforeTaxi and (utils.readDataRefFloat("laminar/B738/buttons/capt_6_pack_pos") == 1 or utils.readDataRefFloat("laminar/B738/buttons/fo_6_pack_pos") == 1) then
			recallCheckedBeforeTaxi = true
		end

		if not takeoffConfigChecked and utils.checkArrayValuesAnyFloat("sim/cockpit2/engine/actuators/throttle_ratio", 0, 2, function(v) return v >= 0.5 end) then
			takeoffConfigChecked = true
		end
	else
		-- Engine has been shut down, reset the values for the next sector
		flightControlYokeFullForwardChecked = false
		flightControlYokeFullBackwardChecked = false
		flightControlYokeFullLeftChecked = false
		flightControlYokeFullRightChecked = false
		flightControlRudderFullRightChecked = false
		flightControlRudderFullLeftChecked = false
		recallCheckedBeforeTaxi = false
		takeoffConfigChecked = false
		recallCheckedLanding = false
		isMissedApproach = false
	end

	-- Only check certain values if the radio altimeter displays a value, to prevent any decrease in performance
	if radioAltimeterActive then
		if not recallCheckedLanding and (utils.readDataRefFloat("laminar/B738/buttons/capt_6_pack_pos") == 1 or utils.readDataRefFloat("laminar/B738/buttons/fo_6_pack_pos") == 1) then
			recallCheckedLanding = true
		end
	else
		-- Radio altimeter is no longer active, reset the values for the next sector or the next approach in case of a go around
		recallCheckedLanding = false
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

--- Gets the key of the response sound file for the start switches checklist item
-- @treturn string The key of the response sound file to play
local function getResponseStartSwitches()
	if utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 2 then
		return "CONT"
	end

	return "OFF"
end

--- Gets the key of the response sound file for the required flaps checklist item
-- @treturn string The key of the response sound file to play
local function getResponseFlapsRequiredSet()
	local requiredFlaps = utils.readDataRefFloat("laminar/B738/FMS/takeoff_flaps")

	if requiredFlaps == 1 then
		return "FLAPS_1_REQUIRED_AND_SELECTED_GREEN_LIGHT"
	end

	if requiredFlaps == 5 then
		return "FLAPS_5_REQUIRED_AND_SELECTED_GREEN_LIGHT"
	end

	if requiredFlaps == 10 then
		return "FLAPS_10_REQUIRED_AND_SELECTED_GREEN_LIGHT"
	end

	if requiredFlaps == 15 then
		return "FLAPS_15_REQUIRED_AND_SELECTED_GREEN_LIGHT"
	end

	if requiredFlaps == 25 then
		return "FLAPS_25_REQUIRED_AND_SELECTED_GREEN_LIGHT"
	end

	return "CHECKED"
end

--- Gets the key of the response sound file for the set flaps checklist item
-- @treturn string The key of the response sound file to play
local function getResponseFlapsSet()
	local flapLeverPos = utils.readDataRefFloat("laminar/B738/flt_ctrls/flap_lever")

	if flapLeverPos == 0.125 then
		return "FLAPS_1_SET_GREEN_LIGHT"
	end

	if flapLeverPos == 0.25 then
		return "FLAPS_2_SET_GREEN_LIGHT"
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

	if flapLeverPos == 0.75 then
		return "FLAPS_25_SET_GREEN_LIGHT"
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

	if autobrakeSwitchPosition == 0 then
		return "RTO"
	end

	if autobrakeSwitchPosition == 1 then
		return "OFF"
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

--- Gets the key of the response sound file for the electrical checklist item
-- @treturn string The key of the response sound file to play
local function getResponseElectrical()
	if utils.readDataRefInteger("sim/cockpit/electrical/generator_apu_on") == 1 then
		return "APU_ON_THE_BUS"
	end

	if utils.readDataRefInteger("sim/cockpit/electrical/gpu_on") == 1 then
		return "GPU_ON_THE_BUS"
	end

	return "CHECKED"
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
	voice:addChallengeSoundFile("SafetyInspectionChecklist_Start", "SafetyInspectionChecklist_Start.wav")
	voice:addChallengeSoundFile("SafetyInspectionChecklist_SurfacesChocks", "SafetyInspectionChecklist_SurfacesChocks.wav")
	voice:addChallengeSoundFile("SafetyInspectionChecklist_MaintenanceStatus", "SafetyInspectionChecklist_MaintenanceStatus.wav")
	voice:addChallengeSoundFile("SafetyInspectionChecklist_Battery", "SafetyInspectionChecklist_Battery.wav")
	voice:addChallengeSoundFile("SafetyInspectionChecklist_ElectricHydraulicPumps", "SafetyInspectionChecklist_ElectricHydraulicPumps.wav")
	voice:addChallengeSoundFile("SafetyInspectionChecklist_LandingGearLever", "SafetyInspectionChecklist_LandingGearLever.wav")
	voice:addChallengeSoundFile("SafetyInspectionChecklist_ShipsLibrary", "SafetyInspectionChecklist_ShipsLibrary.wav")
	voice:addChallengeSoundFile("SafetyInspectionChecklist_Completed", "SafetyInspectionChecklist_Completed.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Start", "BeforeStartChecklistToTheLine_Start.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_IRSModeSelectors", "BeforeStartChecklistToTheLine_IRSModeSelectors.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_GearPins", "BeforeStartChecklistToTheLine_GearPins.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_LightTest", "BeforeStartChecklistToTheLine_LightTest.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Oxygen", "BeforeStartChecklistToTheLine_Oxygen.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_YawDamper", "BeforeStartChecklistToTheLine_YawDamper.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_NavTransferDisplaySwitches", "BeforeStartChecklistToTheLine_NavTransferDisplaySwitches.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Fuel", "BeforeStartChecklistToTheLine_Fuel.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_FuelPumps", "BeforeStartChecklistToTheLine_FuelPumps.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_CabUtilIfeGalleyPower", "BeforeStartChecklistToTheLine_CabUtilIfeGalleyPower.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_EmergencyExitLights", "BeforeStartChecklistToTheLine_EmergencyExitLights.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_FastenBelts", "BeforeStartChecklistToTheLine_FastenBelts.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_WindowHeat", "BeforeStartChecklistToTheLine_WindowHeat.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_AirConditioning", "BeforeStartChecklistToTheLine_AirConditioning.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Press", "BeforeStartChecklistToTheLine_Press.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_PressModeSelector", "BeforeStartChecklistToTheLine_PressModeSelector.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Instruments", "BeforeStartChecklistToTheLine_Instruments.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Autobrake", "BeforeStartChecklistToTheLine_Autobrake.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Hydraulics", "BeforeStartChecklistToTheLine_Hydraulics.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Speedbrake", "BeforeStartChecklistToTheLine_Speedbrake.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Parkingbrake", "BeforeStartChecklistToTheLine_Parkingbrake.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_StabTrimCutoutSwitches", "BeforeStartChecklistToTheLine_StabTrimCutoutSwitches.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_WheelWellFireWarning", "BeforeStartChecklistToTheLine_WheelWellFireWarning.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_RadiosRadarTransponder", "BeforeStartChecklistToTheLine_RadiosRadarTransponder.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_RudderAileronTrims", "BeforeStartChecklistToTheLine_RudderAileronTrims.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_TakeoffBriefing", "BeforeStartChecklistToTheLine_TakeoffBriefing.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_PA", "BeforeStartChecklistToTheLine_PA.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_FmcCdu", "BeforeStartChecklistToTheLine_FmcCdu.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_N1IasBugs", "BeforeStartChecklistToTheLine_N1IasBugs.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_StabTrim", "BeforeStartChecklistToTheLine_StabTrim.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_PerformanceWeightBalance", "BeforeStartChecklistToTheLine_PerformanceWeightBalance.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_EFB", "BeforeStartChecklistToTheLine_EFB.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Phones", "BeforeStartChecklistToTheLine_Phones.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_FlightdeckWindowCockpitDoor", "BeforeStartChecklistToTheLine_FlightdeckWindowCockpitDoor.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Doors", "BeforeStartChecklistToTheLine_Doors.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Passengers", "BeforeStartChecklistToTheLine_Passengers.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistToTheLine_Completed", "BeforeStartChecklistToTheLine_Completed.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistBelowTheLine_Start", "BeforeStartChecklistBelowTheLine_Start.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistBelowTheLine_AirCondPacks", "BeforeStartChecklistBelowTheLine_AirCondPacks.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistBelowTheLine_AntiCollisionLight", "BeforeStartChecklistBelowTheLine_AntiCollisionLight.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistBelowTheLine_ParkingBreak", "BeforeStartChecklistBelowTheLine_ParkingBreak.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistBelowTheLine_Transponder", "BeforeStartChecklistBelowTheLine_Transponder.wav")
	voice:addChallengeSoundFile("BeforeStartChecklistBelowTheLine_Completed", "BeforeStartChecklistBelowTheLine_Completed.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_Start", "BeforeTaxiChecklist_Start.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_Generators", "BeforeTaxiChecklist_Generators.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_APU", "BeforeTaxiChecklist_APU.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_StartSwitches", "BeforeTaxiChecklist_StartSwitches.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_ProbeHeat", "BeforeTaxiChecklist_ProbeHeat.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_AntiIce", "BeforeTaxiChecklist_AntiIce.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_AirConditioning", "BeforeTaxiChecklist_AirConditioning.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_IsolationValve", "BeforeTaxiChecklist_IsolationValve.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_Flaps", "BeforeTaxiChecklist_Flaps.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_StabTrim", "BeforeTaxiChecklist_StabTrim.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_StartLever", "BeforeTaxiChecklist_StartLever.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_FlightControls", "BeforeTaxiChecklist_FlightControls.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_Recall", "BeforeTaxiChecklist_Recall.wav")
	voice:addChallengeSoundFile("BeforeTaxiChecklist_Completed", "BeforeTaxiChecklist_Completed.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistToTheLine_Start", "BeforeTakeoffChecklistToTheLine_Start.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistToTheLine_Config", "BeforeTakeoffChecklistToTheLine_Config.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistToTheLine_Flaps", "BeforeTakeoffChecklistToTheLine_Flaps.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistToTheLine_StabTrim", "BeforeTakeoffChecklistToTheLine_StabTrim.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistToTheLine_TakeoffBriefing", "BeforeTakeoffChecklistToTheLine_TakeoffBriefing.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistToTheLine_Cabin", "BeforeTakeoffChecklistToTheLine_Cabin.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistToTheLine_Completed", "BeforeTakeoffChecklistToTheLine_Completed.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistBelowTheLine_Start", "BeforeTakeoffChecklistBelowTheLine_Start.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistBelowTheLine_MCP", "BeforeTakeoffChecklistBelowTheLine_MCP.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistBelowTheLine_Transponder", "BeforeTakeoffChecklistBelowTheLine_Transponder.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistBelowTheLine_StrobeLights", "BeforeTakeoffChecklistBelowTheLine_StrobeLights.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistBelowTheLine_LandingLights", "BeforeTakeoffChecklistBelowTheLine_LandingLights.wav")
	voice:addChallengeSoundFile("BeforeTakeoffChecklistBelowTheLine_Completed", "BeforeTakeoffChecklistBelowTheLine_Completed.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_Start", "AfterTakeoffChecklist_Start.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_AirCondPress", "AfterTakeoffChecklist_AirCondPress.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_EngineStartSwitches", "AfterTakeoffChecklist_EngineStartSwitches.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_LandingGear", "AfterTakeoffChecklist_LandingGear.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_Autobrake", "AfterTakeoffChecklist_Autobrake.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_Flaps", "AfterTakeoffChecklist_Flaps.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_Altimeters", "AfterTakeoffChecklist_Altimeters.wav")
	voice:addChallengeSoundFile("AfterTakeoffChecklist_Completed", "AfterTakeoffChecklist_Completed.wav")
	voice:addChallengeSoundFile("DescentChecklist_Start", "DescentChecklist_Start.wav")
	voice:addChallengeSoundFile("DescentChecklist_Pressurization", "DescentChecklist_Pressurization.wav")
	voice:addChallengeSoundFile("DescentChecklist_AntiIce", "DescentChecklist_AntiIce.wav")
	voice:addChallengeSoundFile("DescentChecklist_ApproachBriefingFuel", "DescentChecklist_ApproachBriefingFuel.wav")
	voice:addChallengeSoundFile("DescentChecklist_IasAltBugs", "DescentChecklist_IasAltBugs.wav")
	voice:addChallengeSoundFile("DescentChecklist_Completed", "DescentChecklist_Completed.wav")
	voice:addChallengeSoundFile("ApproachChecklist_Start", "ApproachChecklist_Start.wav")
	voice:addChallengeSoundFile("ApproachChecklist_AltsInst", "ApproachChecklist_AltsInst.wav")
	voice:addChallengeSoundFile("ApproachChecklist_ApproachAids", "ApproachChecklist_ApproachAids.wav")
	voice:addChallengeSoundFile("ApproachChecklist_Completed", "ApproachChecklist_Completed.wav")
	voice:addChallengeSoundFile("LandingChecklist_Start", "LandingChecklist_Start.wav")
	voice:addChallengeSoundFile("LandingChecklist_StartSwitches", "LandingChecklist_StartSwitches.wav")
	voice:addChallengeSoundFile("LandingChecklist_Recall", "LandingChecklist_Recall.wav")
	voice:addChallengeSoundFile("LandingChecklist_Speedbrake", "LandingChecklist_Speedbrake.wav")
	voice:addChallengeSoundFile("LandingChecklist_LandingGear", "LandingChecklist_LandingGear.wav")
	voice:addChallengeSoundFile("LandingChecklist_Autobrake", "LandingChecklist_Autobrake.wav")
	voice:addChallengeSoundFile("LandingChecklist_Flaps", "LandingChecklist_Flaps.wav")
	voice:addChallengeSoundFile("LandingChecklist_LandingLights", "LandingChecklist_LandingLights.wav")
	voice:addChallengeSoundFile("LandingChecklist_Completed", "LandingChecklist_Completed.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_Start", "ShutdownChecklist_Start.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_FuelPumps", "ShutdownChecklist_FuelPumps.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_Electrical", "ShutdownChecklist_Electrical.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_FastenBelts", "ShutdownChecklist_FastenBelts.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_WindowHeat", "ShutdownChecklist_WindowHeat.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_ProbeHeat", "ShutdownChecklist_ProbeHeat.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_AntiIce", "ShutdownChecklist_AntiIce.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_ElectricHydraulicPumps", "ShutdownChecklist_ElectricHydraulicPumps.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_VoiceRecorder", "ShutdownChecklist_VoiceRecorder.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_AirCondPacks", "ShutdownChecklist_AirCondPacks.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_EngineBleed", "ShutdownChecklist_EngineBleed.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_ApuBleed", "ShutdownChecklist_ApuBleed.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_ExteriorLights", "ShutdownChecklist_ExteriorLights.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_StartSwitches", "ShutdownChecklist_StartSwitches.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_Autobrake", "ShutdownChecklist_Autobrake.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_Speedbrake", "ShutdownChecklist_Speedbrake.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_Flaps", "ShutdownChecklist_Flaps.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_ParkingBrake", "ShutdownChecklist_ParkingBrake.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_StartLevers", "ShutdownChecklist_StartLevers.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_WeatherRadar", "ShutdownChecklist_WeatherRadar.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_Transponder", "ShutdownChecklist_Transponder.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_CvrCB", "ShutdownChecklist_CvrCB.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_CockpitDoor", "ShutdownChecklist_CockpitDoor.wav")
	voice:addChallengeSoundFile("ShutdownChecklist_Completed", "ShutdownChecklist_Completed.wav")
	voice:addChallengeSoundFile("SecureChecklist_Start", "SecureChecklist_Start.wav")
	voice:addChallengeSoundFile("SecureChecklist_IrsModeSelectors", "SecureChecklist_IrsModeSelectors.wav")
	voice:addChallengeSoundFile("SecureChecklist_CabUtilIfeGalleyPower", "SecureChecklist_CabUtilIfeGalleyPower.wav")
	voice:addChallengeSoundFile("SecureChecklist_EmergencyExitLights", "SecureChecklist_EmergencyExitLights.wav")
	voice:addChallengeSoundFile("SecureChecklist_AirCondPacks", "SecureChecklist_AirCondPacks.wav")
	voice:addChallengeSoundFile("SecureChecklist_TrimAir", "SecureChecklist_TrimAir.wav")
	voice:addChallengeSoundFile("SecureChecklist_ApuGroundPower", "SecureChecklist_ApuGroundPower.wav")
	voice:addChallengeSoundFile("SecureChecklist_Battery", "SecureChecklist_Battery.wav")
	voice:addChallengeSoundFile("SecureChecklist_Completed", "SecureChecklist_Completed.wav")
end
--- Adds the mapping of the challenge sound files to a waveFileVoice.
-- @tparam waveFileVoice voice The voice.
local function addResponseSoundFilesMapping(voice)
	voice:addResponseSoundFile("CHECKED", "Response_Checked.wav")
	voice:addResponseSoundFile("ON", "Response_On.wav")
	voice:addResponseSoundFile("DOWN", "Response_Down.wav")
	voice:addResponseSoundFile("NAV", "Response_NAV.wav")
	voice:addResponseSoundFile("REMOVED", "Response_Removed.wav")
	voice:addResponseSoundFile("TESTED, 100%", "Response_Tested100Percent.wav")
	voice:addResponseSoundFile("NORMAL, AUTO", "Response_NormalAuto.wav")
	voice:addResponseSoundFile("FUEL_PUMPS_4_ON", "Response_Fuel4PumpsOn.wav")
	voice:addResponseSoundFile("FUEL_PUMPS_6_ON", "Response_Fuel6PumpsOn.wav")
	voice:addResponseSoundFile("ARMED", "Response_Armed.wav")
	voice:addResponseSoundFile("AUTO", "Response_Auto.wav")
	voice:addResponseSoundFile("X-CHECKED", "Response_XChecked.wav")
	voice:addResponseSoundFile("RTO", "Response_RTO.wav")
	voice:addResponseSoundFile("NORMAL", "Response_Normal.wav")
	voice:addResponseSoundFile("DOWN DETENT", "Response_DownDetent.wav")
	voice:addResponseSoundFile("SET", "Response_Set.wav")
	voice:addResponseSoundFile("SET & STBY", "Response_SetStby.wav")
	voice:addResponseSoundFile("FREE & ZERO", "Response_FreeZero.wav")
	voice:addResponseSoundFile("COMPLETE", "Response_Complete.wav")
	voice:addResponseSoundFile("N1_IAS_AUTO_VSPEEDS_SET", "Response_N1IasAutoVspeedsSet.wav")
	voice:addResponseSoundFile("AIRPLANE MODE, STOWED", "Response_AirplaneModeStowed.wav")
	voice:addResponseSoundFile("OFF", "Response_Off.wav")
	voice:addResponseSoundFile("CLOSED", "Response_Closed.wav")
	voice:addResponseSoundFile("SEATED", "Response_Seated.wav")
	voice:addResponseSoundFile("ALT OFF", "Response_AltOff.wav")
	voice:addResponseSoundFile("CONT", "Response_Cont.wav")
	voice:addResponseSoundFile("PACKS AUTO, BLEEDS ON", "Response_PacksAutoBleedsOn.wav")
	voice:addResponseSoundFile("IDLE_DETENT", "Response_IdleDetent.wav")
	voice:addResponseSoundFile("FLAPS_1_REQUIRED_AND_SELECTED_GREEN_LIGHT", "Response_Flaps1RequiredSelectedGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_5_REQUIRED_AND_SELECTED_GREEN_LIGHT", "Response_Flaps5RequiredSelectedGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_10_REQUIRED_AND_SELECTED_GREEN_LIGHT", "Response_Flaps10RequiredSelectedGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_15_REQUIRED_AND_SELECTED_GREEN_LIGHT", "Response_Flaps15RequiredSelectedGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_25_REQUIRED_AND_SELECTED_GREEN_LIGHT", "Response_Flaps25RequiredSelectedGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_1_SET_GREEN_LIGHT", "Response_Flaps1SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_2_SET_GREEN_LIGHT", "Response_Flaps2SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_5_SET_GREEN_LIGHT", "Response_Flaps5SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_10_SET_GREEN_LIGHT", "Response_Flaps10SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_15_SET_GREEN_LIGHT", "Response_Flaps15SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_25_SET_GREEN_LIGHT", "Response_Flaps25SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_30_SET_GREEN_LIGHT", "Response_Flaps30SetGreenLight.wav")
	voice:addResponseSoundFile("FLAPS_40_SET_GREEN_LIGHT", "Response_Flaps40SetGreenLight.wav")
	voice:addResponseSoundFile("REVIEWED", "Response_Reviewed.wav")
	voice:addResponseSoundFile("SECURED", "Response_Secured.wav")
	voice:addResponseSoundFile("TA/RA", "Response_TARA.wav")
	voice:addResponseSoundFile("UP & OFF", "Response_UpOff.wav")
	voice:addResponseSoundFile("UP, NO LIGHTS", "Response_UpNoLights.wav")
	voice:addResponseSoundFile("DISCUSSED", "Response_Discussed.wav")
	voice:addResponseSoundFile("CHECKED & SET", "Response_CheckedSet.wav")
	voice:addResponseSoundFile("SET & X-CHECKED", "Response_SetXchecked.wav")
	voice:addResponseSoundFile("ARMED_GREEN_LIGHT", "Response_ArmedGreenLight.wav")
	voice:addResponseSoundFile("DOWN, 3 GREENS", "Response_Down3Greens.wav")
	voice:addResponseSoundFile("AUTOBRAKE_1", "Response_Autobrake1Set.wav")
	voice:addResponseSoundFile("AUTOBRAKE_2", "Response_Autobrake2Set.wav")
	voice:addResponseSoundFile("AUTOBRAKE_3", "Response_Autobrake3Set.wav")
	voice:addResponseSoundFile("AUTOBRAKE_MAX", "Response_AutobrakeMaxSet.wav")
	voice:addResponseSoundFile("APU_ON_THE_BUS", "Response_ApuOnTheBus.wav")
	voice:addResponseSoundFile("GPU_ON_THE_BUS", "Response_GpuOnTheBus.wav")
	voice:addResponseSoundFile("CUTOFF", "Response_CutOff.wav")
	voice:addResponseSoundFile("IN", "Response_In.wav")
	voice:addResponseSoundFile("STBY", "Response_Stby.wav")
	voice:addResponseSoundFile("UNLOCKED", "Response_Unlocked.wav")
end

-- Set the callbacks for the updates
ziboDefaultSOP:addDoOftenCallback(updateDataRefVariablesOften)
ziboDefaultSOP:addDoEveryFrameCallback(updateDataRefVariablesEveryFrame)

-- Reset the appropriate checklists for a turnaround
shutdownChecklistTransit:addCompletedCallback(function() resetAllChecklistsExcept(safetyInspectionChecklist) end)

-- Reset all checklists after the last checklist has been completed
secureChecklist:addCompletedCallback(function() resetAllChecklistsExcept(nil) end)

-- Add the mappings of the challenge sound
addChallengeSoundFilesMapping(voiceAndy)
addChallengeSoundFilesMapping(voiceLars)
addChallengeSoundFilesMapping(voiceFlightdeck2Sim)

-- Add the mappings of the response sound
addResponseSoundFilesMapping(voiceAndy)
addResponseSoundFilesMapping(voicePatrick)
addResponseSoundFilesMapping(voiceLars)
addResponseSoundFilesMapping(voiceFlightdeck2Sim)

-- Add the available fail sound files
-- Each time a checklist item does not meet its condition, a random fail sound is selected and played
-- Each voice can have its own fail sound files
voiceAndy:addFailSoundFile("Fail_AhThis.wav")
voiceAndy:addFailSoundFile("Fail_AreYouSure.wav")
voiceAndy:addFailSoundFile("Fail_CheckAgain.wav")
voiceAndy:addFailSoundFile("Fail_Damn.wav")
voiceAndy:addFailSoundFile("Fail_Hmm.wav")
voiceAndy:addFailSoundFile("Fail_LetsSee.wav")
voiceAndy:addFailSoundFile("Fail_No.wav")
voiceAndy:addFailSoundFile("Fail_NotAgain.wav")
voiceAndy:addFailSoundFile("Fail_Really.wav")
voiceAndy:addFailSoundFile("Fail_RealPilot.wav")
voiceAndy:addFailSoundFile("Fail_Whoops.wav")
voiceAndy:addFailSoundFile("Fail_YouSure.wav")

voicePatrick:addFailSoundFile("Fail_Damn.wav")
voicePatrick:addFailSoundFile("Fail_Hmm.wav")
voicePatrick:addFailSoundFile("Fail_AhThis.wav")
voicePatrick:addFailSoundFile("Fail_NotAgain.wav")
voicePatrick:addFailSoundFile("Fail_LetsSee.wav")

voiceLars:addFailSoundFile("Fail_AreYouSure.wav")
voiceLars:addFailSoundFile("Fail_CheckAgain.wav")
voiceLars:addFailSoundFile("Fail_No.wav")
voiceLars:addFailSoundFile("Fail_Really.wav")
voiceLars:addFailSoundFile("Fail_YouSure.wav")

voiceFlightdeck2Sim:addFailSoundFile("Fail_AhThis.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_AreYouSure.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_CheckThatAgain.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_Damn.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_Hmm.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_LetsSee.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_No.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_NotAgain.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_Really.wav")
voiceFlightdeck2Sim:addFailSoundFile("Fail_YouSure.wav")

-- ################# SAFETY INSPECTION
safetyInspectionChecklist:addItem(soundChecklistItem:new("SafetyInspectionChecklist_Start"))
safetyInspectionChecklist:addItem(automaticChecklistItem:new("SURFACES & CHOCKS", "CHECKED", "SafetyInspectionChecklist_SurfacesChocks", function() return true end))
safetyInspectionChecklist:addItem(automaticChecklistItem:new("MAINTENANCE STATUS", "CHECKED", "SafetyInspectionChecklist_MaintenanceStatus", function() return true end))
safetyInspectionChecklist:addItem(automaticChecklistItem:new("BATTERY", "ON", "SafetyInspectionChecklist_Battery", function() return utils.readDataRefFloat("laminar/B738/electric/battery_pos") == 1 end))
safetyInspectionChecklist:addItem(automaticChecklistItem:new("ELECTRIC HYDRAULIC PUMPS", "ON", "SafetyInspectionChecklist_ElectricHydraulicPumps", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/electric_hydro_pumps1_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/electric_hydro_pumps2_pos") == 1 end))
safetyInspectionChecklist:addItem(automaticChecklistItem:new("LANDING GEAR LEVER", "DOWN", "SafetyInspectionChecklist_LandingGearLever", function() return utils.readDataRefFloat("laminar/B738/controls/gear_handle_down") == 1 end))
safetyInspectionChecklist:addItem(automaticChecklistItem:new("SHIPS LIBRARY", "CHECKED", "SafetyInspectionChecklist_ShipsLibrary", function() return true end))
safetyInspectionChecklist:addItem(soundChecklistItem:new("SafetyInspectionChecklist_Completed"))

-- ################# BEFORE START TO THE LINE
beforeStartChecklistToTheLine:addItem(soundChecklistItem:new("BeforeStartChecklistToTheLine_Start"))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("IRS MODE SELECTORS", "NAV", "BeforeStartChecklistToTheLine_IRSModeSelectors", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/irs_left") == 2 and utils.readDataRefFloat("laminar/B738/toggle_switch/irs_right") == 2 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("GEAR PINS", "REMOVED", "BeforeStartChecklistToTheLine_GearPins", function() return true end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("LIGHT TEST", "CHECKED", "BeforeStartChecklistToTheLine_LightTest", function() return lightTestDone end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("OXYGEN", "TESTED, 100%", "BeforeStartChecklistToTheLine_Oxygen", function() return oxygenChecked end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("YAW DAMPER", "ON", "BeforeStartChecklistToTheLine_YawDamper", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/yaw_dumper_pos") == 1 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("NAV TRANSFER & DISPLAY SWITCHES", "NORMAL, AUTO", "BeforeStartChecklistToTheLine_NavTransferDisplaySwitches", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/vhf_nav_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/irs_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/fmc_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/dspl_ctrl_pnl") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/dspl_source") == 0 end))
beforeStartChecklistToTheLine:addItem(manualDynamicResponseChecklistItem:new("FUEL", "__ REQ, __ ONBOARD", "BeforeStartChecklistToTheLine_Fuel", function() return "CHECKED" end))
beforeStartChecklistToTheLine:addItem(automaticDynamicResponseChecklistItem:new("FUEL PUMPS", "ON", "BeforeStartChecklistToTheLine_FuelPumps", getResponseFuelPumps, function() return utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft1") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft2") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt1") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt2") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr1") == utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr2") end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("CAB/UTIL, IFE/GALLEY POWER", "ON", "BeforeStartChecklistToTheLine_CabUtilIfeGalleyPower", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/cab_util_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/ife_pass_seat_pos") == 1 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("EMERGENCY EXIT LIGHTS", "ARMED", "BeforeStartChecklistToTheLine_EmergencyExitLights", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/emer_exit_lights") == 1 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("FASTEN BELTS", "ON", "BeforeStartChecklistToTheLine_FastenBelts", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/seatbelt_sign_pos") == 2 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("WINDOW HEAT", "ON", "BeforeStartChecklistToTheLine_WindowHeat", function() return utils.readDataRefFloat("laminar/B738/ice/window_heat_l_fwd_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_l_side_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_fwd_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_side_pos") == 1 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("AIR COND", "PACKS AUTO, BLEEDS ON", "BeforeStartChecklistToTheLine_AirConditioning", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_1_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_2_pos") == 1 end))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("PRESS", "SET", "BeforeStartChecklistToTheLine_Press"))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("PRESSURIZATION MODE SELECTOR", "AUTO", "BeforeStartChecklistToTheLine_PressModeSelector", function() return utils.readDataRefFloat("laminar/B738/pressurization_mode") == 1 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("INSTRUMENTS", "X-CHECKED", "BeforeStartChecklistToTheLine_Instruments", function() return true end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("AUTOBRAKE", "RTO", "BeforeStartChecklistToTheLine_Autobrake", function() return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos") == 0 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("HYDRAULICS", "NORMAL", "BeforeStartChecklistToTheLine_Hydraulics", function() return utils.readDataRefFloat("laminar/B738/hydraulic/A_pressure", 0) >= 2800 and utils.readDataRefFloat("laminar/B738/hydraulic/B_pressure", 0) >= 2800 and utils.readDataRefFloat("laminar/B738/hydraulic/hyd_A_qty", 0) >= 76 and utils.readDataRefFloat("laminar/B738/hydraulic/hyd_B_qty", 0) >= 76 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("SPEEDBRAKE", "DOWN DETENT", "BeforeStartChecklistToTheLine_Speedbrake", function() return utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever") == 0 and utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever_stop") == 0 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("PARKING BRAKE", "SET", "BeforeStartChecklistToTheLine_Parkingbrake", function() return utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("STAB TRIM CUTOUT SWITCHES", "NORMAL", "BeforeStartChecklistToTheLine_StabTrimCutoutSwitches", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/el_trim_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/ap_trim_pos") == 0 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("WHEEL WELL FIRE WARNING", "CHECKED", "BeforeStartChecklistToTheLine_WheelWellFireWarning", function() return fireWarningTestDone end))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("RADIOS, RADAR * TXPDR", "SET & STBY", "BeforeStartChecklistToTheLine_RadiosRadarTransponder"))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("RUDDER & AILERON TRIMS", "FREE & ZERO", "BeforeStartChecklistToTheLine_RudderAileronTrims", function() return math.abs(utils.readDataRefFloat("sim/cockpit2/controls/rudder_trim", 0)) < 0.01 and math.abs(utils.readDataRefFloat("sim/cockpit2/controls/aileron_trim", 0)) < 0.1 end))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("TAKEOFF BRIEFING", "DISCUSSED", "BeforeStartChecklistToTheLine_TakeoffBriefing"))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("PA", "COMPLETE", "BeforeStartChecklistToTheLine_PA"))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("FMC/CDU", "SET", "BeforeStartChecklistToTheLine_FmcCdu"))
beforeStartChecklistToTheLine:addItem(automaticDynamicResponseChecklistItem:new("N1 & IAS BUGS", "AUTO __ / __ SET", "BeforeStartChecklistToTheLine_N1IasBugs", function() return "N1_IAS_AUTO_VSPEEDS_SET" end, function() return utils.readDataRefFloat("laminar/B738/toggle_switch/n1_set_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/spd_ref") == 0 and utils.readDataRefFloat("laminar/B738/FMS/v1_set", 0) > 0 and utils.readDataRefFloat("laminar/B738/FMS/vr_set", 0) > 0 and utils.readDataRefFloat("laminar/B738/FMS/v2_set", 0) > 0 and utils.readDataRefFloat("laminar/B738/FMS/v2_set") == utils.readDataRefFloat("laminar/B738/autopilot/mcp_speed_dial_kts") end))
beforeStartChecklistToTheLine:addItem(automaticDynamicResponseChecklistItem:new("STAB TRIM", "__ SET", "BeforeStartChecklistToTheLine_StabTrim", function() return "SET" end, evaluateStabTrim))
beforeStartChecklistToTheLine:addItem(manualChecklistItem:new("PERFORMANCE, WEIGHT & BALANCE", "CHECKED", "BeforeStartChecklistToTheLine_PerformanceWeightBalance"))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("EFB", "AIRPLANE MODE, STOWED", "BeforeStartChecklistToTheLine_EFB", function() return true end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("PHONES", "OFF", "BeforeStartChecklistToTheLine_Phones", function() return true end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("FLIGHT DECK WINDOWS & COCKPIT DOOR", "CLOSED", "BeforeStartChecklistToTheLine_FlightdeckWindowCockpitDoor", function() return utils.readDataRefFloat("laminar/B738/door/flt_dk_door_ratio") == 0 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("DOORS", "CLOSED", "BeforeStartChecklistToTheLine_Doors", function() return utils.readDataRefFloat("737u/doors/L1") == 0 and utils.readDataRefFloat("737u/doors/L2") == 0 and utils.readDataRefFloat("737u/doors/R1") == 0 and utils.readDataRefFloat("737u/doors/R2") == 0 and utils.readDataRefFloat("737u/doors/aft_Cargo") == 0 and utils.readDataRefFloat("737u/doors/Fwd_Cargo") == 0 and utils.readDataRefFloat("737u/doors/emerg1") == 0 and utils.readDataRefFloat("737u/doors/emerg2") == 0 and utils.readDataRefFloat("737u/doors/emerg3") == 0 and utils.readDataRefFloat("737u/doors/emerg4") == 0 end))
beforeStartChecklistToTheLine:addItem(automaticChecklistItem:new("PASSENGERS", "SEATED", "BeforeStartChecklistToTheLine_Passengers", function() return true end))
beforeStartChecklistToTheLine:addItem(soundChecklistItem:new("BeforeStartChecklistToTheLine_Completed"))

-- ################# BEFORE START TO THE LINE (TRANSIT)
beforeStartChecklistToTheLineTransit:addItem(soundChecklistItem:new("BeforeStartChecklistToTheLine_Start"))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("GEAR PINS", "REMOVED", "BeforeStartChecklistToTheLine_GearPins", function() return true end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("OXYGEN", "TESTED, 100%", "BeforeStartChecklistToTheLine_Oxygen", function() return oxygenChecked end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("YAW DAMPER", "ON", "BeforeStartChecklistToTheLine_YawDamper", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/yaw_dumper_pos") == 1 end))
beforeStartChecklistToTheLineTransit:addItem(manualDynamicResponseChecklistItem:new("FUEL", "__ REQ, __ ONBOARD", "BeforeStartChecklistToTheLine_Fuel", function() return "CHECKED" end))
beforeStartChecklistToTheLineTransit:addItem(automaticDynamicResponseChecklistItem:new("FUEL PUMPS", "ON", "BeforeStartChecklistToTheLine_FuelPumps", getResponseFuelPumps, function() return utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft1") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft2") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt1") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt2") == 1 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr1") == utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr2") end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("FASTEN BELTS", "ON", "BeforeStartChecklistToTheLine_FastenBelts", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/seatbelt_sign_pos") == 2 end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("WINDOW HEAT", "ON", "BeforeStartChecklistToTheLine_WindowHeat", function() return utils.readDataRefFloat("laminar/B738/ice/window_heat_l_fwd_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_l_side_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_fwd_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_side_pos") == 1 end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("AIR COND", "PACKS AUTO, BLEEDS ON", "BeforeStartChecklistToTheLine_AirConditioning", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_1_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_2_pos") == 1 end))
beforeStartChecklistToTheLineTransit:addItem(manualChecklistItem:new("PRESS", "SET", "BeforeStartChecklistToTheLine_Press"))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("PRESSURIZATION MODE SELECTOR", "AUTO", "BeforeStartChecklistToTheLine_PressModeSelector", function() return utils.readDataRefFloat("laminar/B738/pressurization_mode") == 1 end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("INSTRUMENTS", "X-CHECKED", "BeforeStartChecklistToTheLine_Instruments", function() return true end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("AUTOBRAKE", "RTO", "BeforeStartChecklistToTheLine_Autobrake", function() return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos") == 0 end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("PARKING BRAKE", "SET", "BeforeStartChecklistToTheLine_Parkingbrake", function() return utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("STAB TRIM CUTOUT SWITCHES", "NORMAL", "BeforeStartChecklistToTheLine_StabTrimCutoutSwitches", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/el_trim_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/ap_trim_pos") == 0 end))
beforeStartChecklistToTheLineTransit:addItem(manualChecklistItem:new("RADIOS, RADAR * TXPDR", "SET & STBY", "BeforeStartChecklistToTheLine_RadiosRadarTransponder"))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("RUDDER & AILERON TRIMS", "FREE & ZERO", "BeforeStartChecklistToTheLine_RudderAileronTrims", function() return math.abs(utils.readDataRefFloat("sim/cockpit2/controls/rudder_trim", 0)) < 0.01 and math.abs(utils.readDataRefFloat("sim/cockpit2/controls/aileron_trim", 0)) < 0.1 end))
beforeStartChecklistToTheLineTransit:addItem(manualChecklistItem:new("TAKEOFF BRIEFING", "DISCUSSED", "BeforeStartChecklistToTheLine_TakeoffBriefing"))
beforeStartChecklistToTheLineTransit:addItem(manualChecklistItem:new("PA", "COMPLETE", "BeforeStartChecklistToTheLine_PA"))
beforeStartChecklistToTheLineTransit:addItem(manualChecklistItem:new("FMC/CDU", "SET", "BeforeStartChecklistToTheLine_FmcCdu"))
beforeStartChecklistToTheLineTransit:addItem(automaticDynamicResponseChecklistItem:new("N1 & IAS BUGS", "AUTO __ / __ SET", "BeforeStartChecklistToTheLine_N1IasBugs", function() return "N1_IAS_AUTO_VSPEEDS_SET" end, function() return utils.readDataRefFloat("laminar/B738/toggle_switch/n1_set_source") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/spd_ref") == 0 and utils.readDataRefFloat("laminar/B738/FMS/v1_set", 0) > 0 and utils.readDataRefFloat("laminar/B738/FMS/vr_set", 0) > 0 and utils.readDataRefFloat("laminar/B738/FMS/v2_set", 0) > 0 and utils.readDataRefFloat("laminar/B738/FMS/v2_set") == utils.readDataRefFloat("laminar/B738/autopilot/mcp_speed_dial_kts") end))
beforeStartChecklistToTheLineTransit:addItem(automaticDynamicResponseChecklistItem:new("STAB TRIM", "__ SET", "BeforeStartChecklistToTheLine_StabTrim", function() return "SET" end, evaluateStabTrim))
beforeStartChecklistToTheLineTransit:addItem(manualChecklistItem:new("PERFORMANCE, WEIGHT & BALANCE", "CHECKED", "BeforeStartChecklistToTheLine_PerformanceWeightBalance"))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("EFB", "AIRPLANE MODE, STOWED", "BeforeStartChecklistToTheLine_EFB", function() return true end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("PHONES", "OFF", "BeforeStartChecklistToTheLine_Phones", function() return true end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("FLIGHT DECK WINDOWS & COCKPIT DOOR", "CLOSED", "BeforeStartChecklistToTheLine_FlightdeckWindowCockpitDoor", function() return utils.readDataRefFloat("laminar/B738/door/flt_dk_door_ratio") == 0 end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("DOORS", "CLOSED", "BeforeStartChecklistToTheLine_Doors", function() return utils.readDataRefFloat("737u/doors/L1") == 0 and utils.readDataRefFloat("737u/doors/L2") == 0 and utils.readDataRefFloat("737u/doors/R1") == 0 and utils.readDataRefFloat("737u/doors/R2") == 0 and utils.readDataRefFloat("737u/doors/aft_Cargo") == 0 and utils.readDataRefFloat("737u/doors/Fwd_Cargo") == 0 and utils.readDataRefFloat("737u/doors/emerg1") == 0 and utils.readDataRefFloat("737u/doors/emerg2") == 0 and utils.readDataRefFloat("737u/doors/emerg3") == 0 and utils.readDataRefFloat("737u/doors/emerg4") == 0 end))
beforeStartChecklistToTheLineTransit:addItem(automaticChecklistItem:new("PASSENGERS", "SEATED", "BeforeStartChecklistToTheLine_Passengers", function() return true end))
beforeStartChecklistToTheLineTransit:addItem(soundChecklistItem:new("BeforeStartChecklistToTheLine_Completed"))

-- ################# BEFORE START BELOW THE LINE
beforeStartChecklistBelowTheLine:addItem(soundChecklistItem:new("BeforeStartChecklistBelowTheLine_Start"))
beforeStartChecklistBelowTheLine:addItem(automaticChecklistItem:new("AIR COND PACKS", "OFF", "BeforeStartChecklistBelowTheLine_AirCondPacks", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 0 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 0 end))
beforeStartChecklistBelowTheLine:addItem(automaticChecklistItem:new("ANTICOLLISION LIGHT", "ON", "BeforeStartChecklistBelowTheLine_AntiCollisionLight", function() return utils.readDataRefInteger("sim/cockpit2/switches/beacon_on") == 1 end))
beforeStartChecklistBelowTheLine:addItem(automaticChecklistItem:new("PARKING BRAKE", "SET", "BeforeStartChecklistBelowTheLine_ParkingBreak", function() return utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 end))
beforeStartChecklistBelowTheLine:addItem(automaticChecklistItem:new("TRANSPONDER", "ALT OFF", "BeforeStartChecklistBelowTheLine_Transponder", function() return utils.readDataRefFloat("laminar/B738/knob/transponder_pos") == 2 end))
beforeStartChecklistBelowTheLine:addItem(soundChecklistItem:new("BeforeStartChecklistBelowTheLine_Completed"))

-- ################# BEFORE TAXI
beforeTaxiChecklist:addItem(soundChecklistItem:new("BeforeTaxiChecklist_Start"))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("GENERATORS", "ON", "BeforeTaxiChecklist_Generators", function() return utils.checkArrayValuesAllInteger("sim/cockpit/electrical/generator_on", 0, 2, function(v) return v == 1 end) end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("APU", "OFF", "BeforeTaxiChecklist_APU", function() return utils.readDataRefFloat("laminar/B738/spring_toggle_switch/APU_start_pos") == 0 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("START SWITCHES", "CONT", "BeforeTaxiChecklist_StartSwitches", function() return utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 2 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 2 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("PROBE HEAT", "ON", "BeforeTaxiChecklist_ProbeHeat", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/capt_probes_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/fo_probes_pos") == 1 end))
beforeTaxiChecklist:addItem(automaticDynamicResponseChecklistItem:new("ANTI-ICE", "__", "BeforeTaxiChecklist_AntiIce", getResponseAntiIce, function() return utils.readDataRefFloat("laminar/B738/ice/eng1_heat_pos") == utils.readDataRefFloat("laminar/B738/ice/eng2_heat_pos") end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("AIR COND", "PACKS AUTO, BLEEDS ON", "BeforeTaxiChecklist_AirConditioning", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_1_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_2_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_apu_pos") == 0 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("ISOLATION VALVE", "AUTO", "BeforeTaxiChecklist_IsolationValve", function() return utils.readDataRefFloat("laminar/B738/air/isolation_valve_pos") == 1 end))
beforeTaxiChecklist:addItem(automaticDynamicResponseChecklistItem:new("FLAPS", "__ REQ __ SEL, GREEN LIGHT", "BeforeTaxiChecklist_Flaps", getResponseFlapsRequiredSet, function() return utils.readDataRefFloat("laminar/B738/FMS/takeoff_flaps_set") == 1 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") > 0.0 end))
beforeTaxiChecklist:addItem(automaticDynamicResponseChecklistItem:new("STAB TRIM", "__ UNITS REQ, __ SET", "BeforeTaxiChecklist_StabTrim", function() return "SET" end, evaluateStabTrim))
beforeTaxiChecklist:addItem(automaticDynamicResponseChecklistItem:new("START LEVER", "__ IDLE DETENT", "BeforeTaxiChecklist_StartLever", function() return "IDLE_DETENT" end, function() return utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 1 and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 1 end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("FLIGHT CONTROL", "CHECKED", "BeforeTaxiChecklist_FlightControls", function() return flightControlYokeFullForwardChecked and flightControlYokeFullBackwardChecked and flightControlYokeFullLeftChecked and flightControlYokeFullRightChecked and flightControlRudderFullRightChecked and flightControlRudderFullLeftChecked end))
beforeTaxiChecklist:addItem(automaticChecklistItem:new("RECALL", "CHECKED", "BeforeTaxiChecklist_Recall", function() return recallCheckedBeforeTaxi end))
beforeTaxiChecklist:addItem(soundChecklistItem:new("BeforeTaxiChecklist_Completed"))

-- ################# BEFORE TAKEOFF TO THE LINE
beforeTakeoffChecklistToTheLine:addItem(soundChecklistItem:new("BeforeTakeoffChecklistToTheLine_Start"))
beforeTakeoffChecklistToTheLine:addItem(automaticChecklistItem:new("CONFIG", "CHECKED", "BeforeTakeoffChecklistToTheLine_Config", function() return takeoffConfigChecked end))
beforeTakeoffChecklistToTheLine:addItem(automaticDynamicResponseChecklistItem:new("FLAPS", "__ GREEN LIGHT", "BeforeTakeoffChecklistToTheLine_Flaps", getResponseFlapsSet, function() return true end))
beforeTakeoffChecklistToTheLine:addItem(automaticDynamicResponseChecklistItem:new("STAB TRIM", "__ UNITS SET", "BeforeTakeoffChecklistToTheLine_StabTrim", function() return "SET" end, evaluateStabTrim))
beforeTakeoffChecklistToTheLine:addItem(manualChecklistItem:new("TAKEOFF BRIEFING", "REVIEWED", "BeforeTakeoffChecklistToTheLine_TakeoffBriefing"))
beforeTakeoffChecklistToTheLine:addItem(automaticChecklistItem:new("CABIN", "SECURED", "BeforeTakeoffChecklistToTheLine_Cabin", function() return true end))
beforeTakeoffChecklistToTheLine:addItem(soundChecklistItem:new("BeforeTakeoffChecklistToTheLine_Completed"))

-- ################# BEFORE TAKEOFF BELOW THE LINE
beforeTakeoffChecklistBelowTheLine:addItem(soundChecklistItem:new("BeforeTakeoffChecklistBelowTheLine_Start"))
beforeTakeoffChecklistBelowTheLine:addItem(automaticChecklistItem:new("MCP", "SET", "BeforeTakeoffChecklistBelowTheLine_MCP", function() return utils.readDataRefFloat("laminar/B738/autopilot/flight_director_pos") == 1 and utils.readDataRefFloat("laminar/B738/autopilot/flight_director_fo_pos") == 1 and utils.readDataRefFloat("laminar/B738/autopilot/autothrottle_arm_pos") == 1 and (utils.readDataRefFloat("laminar/B738/autopilot/lnav_status") == 1 or utils.readDataRefFloat("laminar/B738/autopilot/hdg_sel_status") == 1) and utils.readDataRefFloat("laminar/B738/FMS/v2_set") == utils.readDataRefFloat("laminar/B738/autopilot/mcp_speed_dial_kts") end))
beforeTakeoffChecklistBelowTheLine:addItem(automaticChecklistItem:new("TRANSPONDER", "TA/RA", "BeforeTakeoffChecklistBelowTheLine_Transponder", function() return utils.readDataRefFloat("laminar/B738/knob/transponder_pos") == 5 end))
beforeTakeoffChecklistBelowTheLine:addItem(automaticChecklistItem:new("STROBE LIGHTS", "ON", "BeforeTakeoffChecklistBelowTheLine_StrobeLights", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/position_light_pos") == 1 end))
beforeTakeoffChecklistBelowTheLine:addItem(automaticChecklistItem:new("LANDING LIGHTS", "ON", "BeforeTakeoffChecklistBelowTheLine_LandingLights", function() return utils.readDataRefFloat("laminar/B738/switch/land_lights_right_pos") == 1 and utils.readDataRefFloat("laminar/B738/switch/land_lights_left_pos") == 1 end))
beforeTakeoffChecklistBelowTheLine:addItem(soundChecklistItem:new("BeforeTakeoffChecklistBelowTheLine_Completed"))

-- ################# AFTER TAKEOFF
afterTakeoffChecklist:addItem(soundChecklistItem:new("AfterTakeoffChecklist_Start"))
afterTakeoffChecklist:addItem(manualChecklistItem:new("AIR COND & PRESS", "SET", "AfterTakeoffChecklist_AirCondPress"))
afterTakeoffChecklist:addItem(automaticDynamicResponseChecklistItem:new("ENGINE START SWITCHES", "__", "AfterTakeoffChecklist_EngineStartSwitches", getResponseStartSwitches, function() return (utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 1 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 1) or (utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 2 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 2 and utils.readDataRefFloat("laminar/B738/ice/eng1_heat_pos") == 1 and utils.readDataRefFloat("laminar/B738/ice/eng2_heat_pos") == 1) end))
afterTakeoffChecklist:addItem(automaticChecklistItem:new("LANDING GEAR", "UP & OFF", "AfterTakeoffChecklist_LandingGear", function() return utils.readDataRefFloat("laminar/B738/controls/gear_handle_down") == 0.5 end))
afterTakeoffChecklist:addItem(automaticDynamicResponseChecklistItem:new("AUTOBRAKE", "OFF", "AfterTakeoffChecklist_Autobrake", getResponseAutobrake, function() if isMissedApproach then return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos", 0) >= 1 else return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos") == 1 end end))
afterTakeoffChecklist:addItem(automaticChecklistItem:new("FLAPS", "UP, NO LIGHTS", "AfterTakeoffChecklist_Flaps", function() return utils.checkArrayValuesAllFloat("laminar/B738/flap_indicator", 0, 2, function(v) return v == 0 end) and utils.readDataRefFloat("laminar/B738/annunciator/slats_transit") == 0 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") == 0 end))
afterTakeoffChecklist:addItem(manualChecklistItem:new("ALTIMETERS", "SET", "AfterTakeoffChecklist_Altimeters"))
afterTakeoffChecklist:addItem(soundChecklistItem:new("AfterTakeoffChecklist_Completed"))

-- ################# DESCENT
descentChecklist:addItem(soundChecklistItem:new("DescentChecklist_Start"))
descentChecklist:addItem(manualDynamicResponseChecklistItem:new("PRESSURIZATION", "LAND ALT __", "DescentChecklist_Pressurization", function() return "SET" end))
descentChecklist:addItem(automaticDynamicResponseChecklistItem:new("ANTI-ICE", "__", "DescentChecklist_AntiIce", getResponseAntiIce, function() return utils.readDataRefFloat("laminar/B738/ice/eng1_heat_pos") == utils.readDataRefFloat("laminar/B738/ice/eng2_heat_pos") end))
descentChecklist:addItem(manualChecklistItem:new("APP BRIEF & FUEL", "DISCUSSED", "DescentChecklist_ApproachBriefingFuel"))
descentChecklist:addItem(manualChecklistItem:new("IAS & ALT BUGS", "CHECKED & SET", "DescentChecklist_IasAltBugs"))
descentChecklist:addItem(soundChecklistItem:new("DescentChecklist_Completed"))

-- ################# APPROACH
approachChecklist:addItem(soundChecklistItem:new("ApproachChecklist_Start"))
approachChecklist:addItem(manualChecklistItem:new("ALT & INST", "SET & X-CHECKED", "ApproachChecklist_AltsInst"))
approachChecklist:addItem(manualChecklistItem:new("APPROACH AIDS", "CHECKED & SET", "ApproachChecklist_ApproachAids"))
approachChecklist:addItem(soundChecklistItem:new("ApproachChecklist_Completed"))

-- ################# LANDING
landingChecklist:addItem(soundChecklistItem:new("LandingChecklist_Start"))
landingChecklist:addItem(automaticChecklistItem:new("START SWITCHES", "CONT", "LandingChecklist_StartSwitches", function() return utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 2 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 2 end))
landingChecklist:addItem(automaticChecklistItem:new("RECALL", "CHECKED", "BeforeTaxiChecklist_Recall", function() return recallCheckedLanding end))
landingChecklist:addItem(automaticDynamicResponseChecklistItem:new("SPEEDBRAKE", "ARMED", "LandingChecklist_Speedbrake", function() return "ARMED_GREEN_LIGHT" end, function() return utils.readDataRefFloat("laminar/B738/annunciator/speedbrake_armed") > 0.0 and utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever") < 0.1 end))
landingChecklist:addItem(automaticChecklistItem:new("LANDING GEAR", "DOWN, 3 GREENS", "LandingChecklist_LandingGear", function() return utils.readDataRefFloat("laminar/B738/controls/gear_handle_down") == 1 and utils.readDataRefFloat("laminar/B738/annunciator/nose_gear_safe") > 0.0 and utils.readDataRefFloat("laminar/B738/annunciator/left_gear_safe") > 0.0 and utils.readDataRefFloat("laminar/B738/annunciator/right_gear_safe") > 0.0 end))
landingChecklist:addItem(automaticDynamicResponseChecklistItem:new("AUTOBRAKE", "__", "LandingChecklist_Autobrake", getResponseAutobrake, function() return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos", 0) >= 2 end))
landingChecklist:addItem(automaticDynamicResponseChecklistItem:new("FLAPS", "__ / __, GREEN LIGHT", "LandingChecklist_Flaps", getResponseFlapsSet, function() return utils.readDataRefFloat("laminar/B738/FMS/approach_flaps_set") == 1 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") > 0.0 end))
landingChecklist:addItem(automaticChecklistItem:new("LANDING LIGHTS", "ON", "LandingChecklist_LandingLights", function() return utils.readDataRefFloat("laminar/B738/switch/land_lights_right_pos") == 1 and utils.readDataRefFloat("laminar/B738/switch/land_lights_left_pos") == 1 end))
landingChecklist:addItem(soundChecklistItem:new("LandingChecklist_Completed"))

-- ################# SHUTDOWN
shutdownChecklist:addItem(soundChecklistItem:new("ShutdownChecklist_Start"))
shutdownChecklist:addItem(automaticChecklistItem:new("FUEL PUMPS", "OFF", "ShutdownChecklist_FuelPumps", function() return utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft1") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_lft2") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt1") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_rgt2") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr1") == 0 and utils.readDataRefFloat("laminar/B738/fuel/fuel_tank_pos_ctr2") == 0 end))
shutdownChecklist:addItem(automaticDynamicResponseChecklistItem:new("ELECTRICAL", "ON __", "ShutdownChecklist_Electrical", getResponseElectrical, function() return utils.readDataRefInteger("sim/cockpit/electrical/generator_apu_on") == 1 or utils.readDataRefInteger("sim/cockpit/electrical/gpu_on") == 1 end))
shutdownChecklist:addItem(automaticChecklistItem:new("FASTEN BELTS", "OFF", "ShutdownChecklist_FastenBelts", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/seatbelt_sign_pos") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("WINDOW HEAT", "OFF", "ShutdownChecklist_WindowHeat", function() return utils.readDataRefFloat("laminar/B738/ice/window_heat_l_fwd_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/window_heat_l_side_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_fwd_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/window_heat_r_side_pos") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("PROBE HEAT", "OFF", "ShutdownChecklist_ProbeHeat", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/capt_probes_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/fo_probes_pos") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("ANTI-ICE", "OFF", "ShutdownChecklist_AntiIce", function() return utils.readDataRefFloat("laminar/B738/ice/eng1_heat_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/eng2_heat_pos") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("ELECTRICAL HYDRAULIC PUMPS", "OFF", "ShutdownChecklist_ElectricHydraulicPumps", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/electric_hydro_pumps1_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/electric_hydro_pumps2_pos") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("VOICE RECORDER", "AUTO", "ShutdownChecklist_VoiceRecorder", function() if not isLevelUpAircraft then return utils.readDataRefFloat("laminar/B738/toggle_switch/vcr") == 0 else return true end end))
shutdownChecklist:addItem(automaticChecklistItem:new("AIR COND PACK(S)", "AUTO", "ShutdownChecklist_AirCondPacks", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 1 end))
shutdownChecklist:addItem(automaticChecklistItem:new("ENG BLEED", "ON", "ShutdownChecklist_EngineBleed", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_1_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_2_pos") == 1 end))
shutdownChecklist:addItem(automaticChecklistItem:new("APU BLEED", "OFF", "ShutdownChecklist_ApuBleed", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_apu_pos") == 0 end))
shutdownChecklist:addItem(automaticDynamicResponseChecklistItem:new("EXTERIOR LIGHTS", "__", "ShutdownChecklist_ExteriorLights", function() return "CHECKED" end, function() return utils.readDataRefInteger("sim/cockpit2/switches/beacon_on") == 0 and utils.readDataRefInteger("sim/cockpit2/switches/navigation_lights_on") == 1 and utils.readDataRefInteger("sim/cockpit2/switches/strobe_lights_on") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_right_pos") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_left_pos") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_ret_left_pos") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_ret_right_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/rwy_light_left") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/rwy_light_right") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/taxi_light_brightness_pos") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("START SWITCHES", "OFF", "ShutdownChecklist_StartSwitches", function() return utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 1 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 1 end))
shutdownChecklist:addItem(automaticChecklistItem:new("AUTOBRAKE", "OFF", "ShutdownChecklist_Autobrake", function() return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos") == 1 end))
shutdownChecklist:addItem(automaticChecklistItem:new("SPEEDBRAKE", "DOWN DETENT", "ShutdownChecklist_Speedbrake", function() return utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever") == 0 and utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever_stop") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("FLAPS", "UP, NO LIGHTS", "ShutdownChecklist_Flaps", function() return utils.checkArrayValuesAllFloat("laminar/B738/flap_indicator", 0, 2, function(v) return v == 0 end) and utils.readDataRefFloat("laminar/B738/annunciator/slats_transit") == 0 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("PARKING BRAKE", "SET", "ShutdownChecklist_ParkingBrake", function() return utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 end))
shutdownChecklist:addItem(automaticChecklistItem:new("START LEVERS", "CUTOFF", "ShutdownChecklist_StartLevers", function() return utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 0 and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("WEATHER RADAR", "OFF", "ShutdownChecklist_WeatherRadar", function() return utils.readDataRefInteger("sim/cockpit2/EFIS/EFIS_weather_on") == 0 end))
shutdownChecklist:addItem(automaticChecklistItem:new("TRANSPONDER", "STBY", "ShutdownChecklist_Transponder", function() return utils.readDataRefFloat("laminar/B738/knob/transponder_pos") == 1 end))
shutdownChecklist:addItem(automaticDynamicResponseChecklistItem:new("CVR CB", "IN / OUT", "ShutdownChecklist_CvrCB", function() return "IN" end, function() return true end))
shutdownChecklist:addItem(automaticChecklistItem:new("COCKPIT DOOR", "UNLOCKED", "ShutdownChecklist_CockpitDoor", function() return utils.readDataRefFloat("laminar/B738/door/flt_dk_door_ratio", 0) > 0 end))
shutdownChecklist:addItem(soundChecklistItem:new("ShutdownChecklist_Completed"))

-- ################# SHUTDOWN (TRANSIT)
shutdownChecklistTransit:addItem(soundChecklistItem:new("ShutdownChecklist_Start"))
shutdownChecklistTransit:addItem(automaticDynamicResponseChecklistItem:new("ELECTRICAL", "ON __", "ShutdownChecklist_Electrical", getResponseElectrical, function() return utils.readDataRefInteger("sim/cockpit/electrical/generator_apu_on") == 1 or utils.readDataRefInteger("sim/cockpit/electrical/gpu_on") == 1 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("FASTEN BELTS", "OFF", "ShutdownChecklist_FastenBelts", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/seatbelt_sign_pos") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("PROBE HEAT", "OFF", "ShutdownChecklist_ProbeHeat", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/capt_probes_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/fo_probes_pos") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("ANTI-ICE", "OFF", "ShutdownChecklist_AntiIce", function() return utils.readDataRefFloat("laminar/B738/ice/eng1_heat_pos") == 0 and utils.readDataRefFloat("laminar/B738/ice/eng2_heat_pos") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("VOICE RECORDER", "ON", "ShutdownChecklist_VoiceRecorder", function() if not isLevelUpAircraft then return utils.readDataRefFloat("laminar/B738/toggle_switch/vcr") == 1 else return true end end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("AIR COND PACK(S)", "AUTO", "ShutdownChecklist_AirCondPacks", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 1 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 1 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("ENG BLEED", "ON", "ShutdownChecklist_EngineBleed", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_1_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_2_pos") == 1 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("APU BLEED", "OFF", "ShutdownChecklist_ApuBleed", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/bleed_air_apu_pos") == 0 end))
shutdownChecklistTransit:addItem(automaticDynamicResponseChecklistItem:new("EXTERIOR LIGHTS", "__", "ShutdownChecklist_ExteriorLights", function() return "CHECKED" end, function() return utils.readDataRefInteger("sim/cockpit2/switches/beacon_on") == 0 and utils.readDataRefInteger("sim/cockpit2/switches/navigation_lights_on") == 1 and utils.readDataRefInteger("sim/cockpit2/switches/strobe_lights_on") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_right_pos") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_left_pos") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_ret_left_pos") == 0 and utils.readDataRefFloat("laminar/B738/switch/land_lights_ret_right_pos") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/rwy_light_left") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/rwy_light_right") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/taxi_light_brightness_pos") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("START SWITCHES", "OFF", "ShutdownChecklist_StartSwitches", function() return utils.readDataRefFloat("laminar/B738/engine/starter1_pos") == 1 and utils.readDataRefFloat("laminar/B738/engine/starter2_pos") == 1 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("AUTOBRAKE", "OFF", "ShutdownChecklist_Autobrake", function() return utils.readDataRefFloat("laminar/B738/autobrake/autobrake_pos") == 1 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("SPEEDBRAKE", "DOWN DETENT", "ShutdownChecklist_Speedbrake", function() return utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever") == 0 and utils.readDataRefFloat("laminar/B738/flt_ctrls/speedbrake_lever_stop") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("FLAPS", "UP, NO LIGHTS", "ShutdownChecklist_Flaps", function() return utils.checkArrayValuesAllFloat("laminar/B738/flap_indicator", 0, 2, function(v) return v == 0 end) and utils.readDataRefFloat("laminar/B738/annunciator/slats_transit") == 0 and utils.readDataRefFloat("laminar/B738/annunciator/slats_extend") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("PARKING BRAKE", "SET", "ShutdownChecklist_ParkingBrake", function() return utils.readDataRefFloat("laminar/B738/parking_brake_pos") == 1 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("START LEVERS", "CUTOFF", "ShutdownChecklist_StartLevers", function() return utils.readDataRefFloat("laminar/B738/engine/mixture_ratio1") == 0 and utils.readDataRefFloat("laminar/B738/engine/mixture_ratio2") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("WEATHER RADAR", "OFF", "ShutdownChecklist_WeatherRadar", function() return utils.readDataRefInteger("sim/cockpit2/EFIS/EFIS_weather_on") == 0 end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("TRANSPONDER", "STBY", "ShutdownChecklist_Transponder", function() return utils.readDataRefFloat("laminar/B738/knob/transponder_pos") == 1 end))
shutdownChecklistTransit:addItem(automaticDynamicResponseChecklistItem:new("CVR CB", "IN / OUT", "ShutdownChecklist_CvrCB", function() return "IN" end, function() return true end))
shutdownChecklistTransit:addItem(automaticChecklistItem:new("COCKPIT DOOR", "UNLOCKED", "ShutdownChecklist_CockpitDoor", function() return utils.readDataRefFloat("laminar/B738/door/flt_dk_door_ratio", 0) > 0 end))
shutdownChecklistTransit:addItem(soundChecklistItem:new("ShutdownChecklist_Completed"))

-- ################# SECURE
secureChecklist:addItem(soundChecklistItem:new("SecureChecklist_Start"))
secureChecklist:addItem(automaticChecklistItem:new("IRS MODE SELECTORS", "OFF", "SecureChecklist_IrsModeSelectors", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/irs_left") == 0 and utils.readDataRefFloat("laminar/B738/toggle_switch/irs_right") == 0 end))
secureChecklist:addItem(automaticChecklistItem:new("CAB/UTIL, IFE/GALLEY POWER", "ON", "SecureChecklist_CabUtilIfeGalleyPower", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/cab_util_pos") == 1 and utils.readDataRefFloat("laminar/B738/toggle_switch/ife_pass_seat_pos") == 1 end))
secureChecklist:addItem(automaticChecklistItem:new("EMERGENCY EXIT LIGHTS", "OFF", "SecureChecklist_EmergencyExitLights", function() return utils.readDataRefFloat("laminar/B738/toggle_switch/emer_exit_lights") == 0 end))
secureChecklist:addItem(automaticChecklistItem:new("AIR COND PACKS", "OFF", "SecureChecklist_AirCondPacks", function() return utils.readDataRefFloat("laminar/B738/air/l_pack_pos") == 0 and utils.readDataRefFloat("laminar/B738/air/r_pack_pos") == 0 end))
if PLANE_ICAO ~= "B736" and PLANE_ICAO ~= "B737" then secureChecklist:addItem(automaticChecklistItem:new("TRIM AIR", "OFF", "SecureChecklist_TrimAir", function() return utils.readDataRefFloat("laminar/B738/air/trim_air_pos") == 0 end)) end
secureChecklist:addItem(automaticChecklistItem:new("APU / GROUND POWER", "OFF", "SecureChecklist_ApuGroundPower", function() return utils.readDataRefFloat("laminar/B738/spring_toggle_switch/APU_start_pos") == 0 and utils.readDataRefFloat("laminar/B738/electric/dc_gnd_service") == 0 end))
secureChecklist:addItem(automaticChecklistItem:new("BATTERY", "OFF", "SecureChecklist_Battery", function() return utils.readDataRefFloat("laminar/B738/electric/battery_pos") == 0 end))
secureChecklist:addItem(soundChecklistItem:new("SecureChecklist_Completed"))