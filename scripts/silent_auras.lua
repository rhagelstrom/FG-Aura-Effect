--
--	Please see the LICENSE.md file included with this distribution for attribution and copyright information.
--

-- luacheck: globals bDebug handleApplyEffect notifyApplySilent notifyApply handleExpireEffect notifyExpireSilent notifyExpire

bDebug = false

OOB_MSGTYPE_AURAAPPLYSILENT = 'applyeffsilent'
OOB_MSGTYPE_AURAEXPIRESILENT = 'expireeffsilent'

local aEffectVarMap
-- Leaving for refernce but the VarMap is ruleset specific. This gets set in onInit()
-- = {
-- 	['nActive'] = { sDBType = 'number', sDBField = 'isactive' },
-- 	['nDuration'] = { sDBType = 'number', sDBField = 'duration', vDBDefault = 1, sDisplay = '[D: %d]' },
-- 	['nGMOnly'] = { sDBType = 'number', sDBField = 'isgmonly' },
-- 	['nInit'] = { sDBType = 'number', sDBField = 'init', sSourceChangeSet = 'initresult', bClearOnUntargetedDrop = true },
-- 	['sName'] = { sDBType = 'string', sDBField = 'label' },
-- 	['sSource'] = { sDBType = 'string', sDBField = 'source_name', bClearOnUntargetedDrop = true },
-- 	['sTarget'] = { sDBType = 'string', bClearOnUntargetedDrop = true },
-- 	['sUnit'] = { sDBType = 'string', sDBField = 'unit' },
-- 	['sAuraSource'] = { sDBType = 'string', sDBField = 'source_aura' },
-- }

local function checkSilentNotification(sSourcePath, targetNodePath)
	local bReturn = false
	local option = OptionsManager.getOption('AURASILENT'):lower()
	if option == 'all' then
		bReturn = true
	else
		local rTarget = ActorManager.resolveActor(DB.findNode(targetNodePath))
		local rSource = ActorManager.resolveActor(DB.findNode(sSourcePath))
		local sRelationship = AuraFactionConditional.getRelationship(rSource, rTarget)
		local sFaction = ActorManager.getFaction(rTarget)
		if sFaction == '' then
			sFaction = 'none'
		end
		if option == sRelationship or option == sFaction then
			bReturn = true
		end
	end
	return bReturn
end

function handleApplyEffect(msgOOB)
	-- Get the target combat tracker node
	local nodeCTEntry = DB.findNode(msgOOB.sTargetNode)
	if not nodeCTEntry then
		ChatManager.SystemMessage(string.format('%s (%s)', Interface.getString('ct_error_effectapplyfail'), msgOOB.sTargetNode))
		return
	end

	-- Reconstitute the effect details
	local rEffect = {}
	for k, _ in pairs(msgOOB) do
		if aEffectVarMap[k] then
			if aEffectVarMap[k].sDBType == 'number' then
				rEffect[k] = tonumber(msgOOB[k]) or 0
			else
				rEffect[k] = msgOOB[k]
			end
		end
	end

	-- Apply the effect
	EffectManager.addEffect(msgOOB.user, msgOOB.identity, nodeCTEntry, rEffect, false)
end

function notifyApplySilent(rEffect, vTargets)
	-- Build OOB message to pass effect to host
	local msgOOB = {}
	msgOOB.type = OOB_MSGTYPE_AURAAPPLYSILENT
	for k, _ in pairs(rEffect) do
		if aEffectVarMap[k] then
			if aEffectVarMap[k].sDBType == 'number' then
				msgOOB[k] = rEffect[k] or aEffectVarMap[k].vDBDefault or 0
			else
				msgOOB[k] = rEffect[k] or aEffectVarMap[k].vDBDefault or ''
			end
		end
	end
	if Session.IsHost then
		msgOOB.user = ''
	else
		msgOOB.user = User.getUsername()
	end
	msgOOB.identity = User.getIdentityLabel()

	-- Send one message for each target
	if type(vTargets) == 'table' then
		for _, v in pairs(vTargets) do
			msgOOB.sTargetNode = v
			Comm.deliverOOBMessage(msgOOB, '')
		end
	else
		msgOOB.sTargetNode = vTargets
		Comm.deliverOOBMessage(msgOOB, '')
	end
end

function notifyApply(rEffect, targetNodePath)
	if rEffect and checkSilentNotification(rEffect.sSource, targetNodePath) then
		AuraEffectSilencer.notifyApplySilent(rEffect, targetNodePath)
	else
		EffectManager.notifyApply(rEffect, targetNodePath)
	end
end

function handleExpireEffect(msgOOB)
	local nodeEffect = DB.findNode(msgOOB.sEffectNode)
	if not nodeEffect then
		ChatManager.SystemMessage(string.format('%s (%s)', Interface.getString('ct_error_effectdeletefail'), msgOOB.sEffectNode))
		return
	end
	local nodeActor = nodeEffect.getChild('...')
	if not nodeActor then
		ChatManager.SystemMessage(string.format('%s (%s)', Interface.getString('ct_error_effectmissingactor'), msgOOB.sEffectNode))
		return
	end
	EffectManager.expireEffect(nodeActor, nodeEffect, tonumber(msgOOB.nExpireClause) or 0)
end

-- luacheck: globals notifyExpireSilent
function notifyExpireSilent(varEffect)
	local nodeEffect = DB.findNode(varEffect)
	if not nodeEffect then
		return false
	end
	DB.deleteNode(nodeEffect)
end

function notifyExpire(varEffect, nMatch, bImmediate)
	local sSource = ''
	if type(varEffect) == 'databasenode' then
		sSource = DB.getValue(varEffect, 'source_name', '')
		varEffect = DB.getPath(varEffect)
	elseif type(varEffect) ~= 'string' then
		return
	end
	local sTarget = DB.getPath(DB.getChild(varEffect, '...'))
	if checkSilentNotification(sSource, sTarget) then
		AuraEffectSilencer.notifyExpireSilent(varEffect)
	else
		EffectManager.notifyExpire(varEffect, nMatch, bImmediate)
	end
end

function onInit()
	-- register option for silent aura messages
	OptionsManager.registerOption2('AURASILENT', false, 'option_header_aura', 'option_label_AURASILENT', 'option_entry_cycler', {
		labels = 'option_val_aura_all|option_val_aura_ally|option_val_aura_enemy|ct_tooltip_factionempty|'
			.. 'ct_tooltip_factionfriend|ct_tooltip_factionneutral|ct_tooltip_factionfoe',
		values = 'all|ally|enemy|none|friend|neutral|foe',
		baselabel = 'option_val_off',
		baseval = 'off',
		default = 'off',
	})
	-- Mod the EffectVarMap to track the source of the aura effect
	EffectManager.registerEffectVar('sAuraSource', { sDBType = 'string', sDBField = 'source_aura' })
	aEffectVarMap = EffectManager.getEffectVarMap()

	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_AURAAPPLYSILENT, handleApplyEffect)
	OOBManager.registerOOBMsgHandler(OOB_MSGTYPE_AURAEXPIRESILENT, handleExpireEffect)
end
