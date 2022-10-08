-- os.execute("cls")
---------------------------------------------------------------------------------------------------
-- QUELQUES UTILITAIRES
---------------------------------------------------------------------------------------------------

local configuration_names = { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z" }
local month_names = { "J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D" }

local display_2d_table = function(args_)
    local line_separator_part = "--------"
    local line_separator_part_length = #line_separator_part
    local data = assert(args_[1])
    local line_names = args_.line_names
    local column_names = args_.column_names
    local justify = function(val_)
        local as_string = type(val_) == "number" and string.format(args_.format or "%4.1f", val_) or tostring(val_)
        local strlen = #as_string
        local needed_whitespaces = line_separator_part_length - strlen
        assert(needed_whitespaces >= 0, "il faut ajouter des caractères à line_separator_part (besoin de" .. needed_whitespaces .. " pour '" .. as_string .. "')")
        local prefix_length = needed_whitespaces // 2
        local suffix_length = needed_whitespaces - prefix_length
        local centered = string.rep(" ", prefix_length) .. as_string .. string.rep(" ", suffix_length)
        return centered
    end
    local num_lines = #data
    local num_columns = #data[1]

    if column_names then
        local header = {}
        for i = 1, num_columns do
            table.insert(header, justify(column_names[i]))
        end
        print("   " .. table.concat(header, " "))
    end

    local line_separator_parts = {}
    for i = 1, num_columns do
        table.insert( line_separator_parts, line_separator_part)
    end
    local line_separator =  "  +" .. table.concat(line_separator_parts, "+") .. "+"
    for line_index = 1, num_lines do
        print(line_separator)
        local line_values = {}
        for _, val in ipairs(data[line_index]) do
            local stringified_val = justify(val)
            table.insert(line_values, stringified_val)
        end
        local line = "|" .. table.concat(line_values, "|") .. "|" .. data[line_index].string_total()
        print((line_names and line_names[line_index] .. " " or "  ") .. line)
    end
    print(line_separator)
end

---------------------------------------------------------------------------------------------------

local make_line = function(t_, with_total_, additional_methods_)
    local line_total = function()
		if not t_.cached_total then
			local total = 0
			for _,v in ipairs(t_) do
				total = total + v
			end
			t_.cached_total = total
		end
        return t_.cached_total
    end

    local line_total_as_string = function()
        return string.format(" T = %04.1f", t_.total())
    end

    local line_with_total = {total = line_total, string_total = line_total_as_string}
    local line_without_total = {total = function() return 0 end, string_total = function() return "" end}
    local index = with_total_ and line_with_total or line_without_total
	if additional_methods_ then
		for name, val in pairs(additional_methods_) do
			index[name] = val
		end
	end

    return setmetatable(t_, {__index = index})
end

---------------------------------------------------------------------------------------------------
-- DONNEES EN ENTREE
---------------------------------------------------------------------------------------------------

-- consommation mensuelle août 2021->septembre 2022
local Monthly_kW_consumption = make_line({ 1640, 1259, 1190, 757, 329, 261, 256, 282, 234, 682, 1221, 1684 }, true)

-- pour simuler l'ajout d'une voiture électrique (attention, le simulateur répartit l'ajout sur la totalité de la journée)
local with_electric_car = 0 -- peugeot e-208 14kWh/100km, 1000km/month: 140 kWh/mois
for month, _ in ipairs(Monthly_kW_consumption) do
		Monthly_kW_consumption[month] = Monthly_kW_consumption[month] + with_electric_car
end

print "kWh consommés de août 2021 à septembre 2022"
display_2d_table{{Monthly_kW_consumption}, column_names = month_names}

---------------------------------------------------------------------------------------------------

-- estimation distribution de la consommation entre le jour et la nuit
local Monthly_nighttime_ratios, Monthly_daytime_ratios, HC_ratios = (function()
	-- base de départ: durée du jour entre lever et coucher du soleil (à calculer), au mileu du mois, à Paris, en minutes
	-- trouvé ici: https://dateandtime.info/fr/citysunrisesunset.php
    local daytime_durations = 
    {
        526, -- 8h46
        615, -- 10h15
        714, -- 11h54
        825, -- 13h45
        920, -- 15h20
        973, -- 16h13
        950, -- 15h50
        866, -- 14h26
        760, -- 12h40
        653, -- 10h53
        554, -- 9h14
        500  -- 8h20
    }
    local nigthtime_ratios, daytime_ratios = {}, {}
	local HC_ratios = {}
    local calendar_day_duration = 24*60
	local HC_duration = 8*60 -- 8h entre 22h et 6h
    for month,daytime_duration in ipairs(daytime_durations) do
        local nighttime_duration = calendar_day_duration - daytime_duration
        table.insert(nigthtime_ratios, nighttime_duration / calendar_day_duration)
        table.insert(daytime_ratios, daytime_duration / calendar_day_duration)
		-- on veut aussi estimer la proportion de la consommation qui se passe pendant les heures creuses.
		-- on fait la supposition qu'elles sont toutes la nuit (aucun intérêt à en avoir le jour pendant qu'on peut auto-consommer)
        table.insert(HC_ratios, HC_duration / nighttime_duration)
    end
	
	
    return nigthtime_ratios, daytime_ratios, HC_ratios
end)()
local Num_days_per_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

---------------------------------------------------------------------------------------------------

local kWc_per_panel = 0.375
-- source: https://re.jrc.ec.europa.eu/pvg_tools/en/
-- production d'un kWc installé en fonction de son azimuth
local kW_per_kWc =
{
    -- abri voiture azimuth +10, pente 30 degrés
    south = { 58.9,  73.41, 107.04, 122.92, 125.8,  137.92, 147.3,  136.03, 116.65, 90.96, 61.68, 52.85 },
    -- toit maison côté est: azimuth -80, pente 32 degrés
    east =  { 35.27, 50.58, 83.4,   107.93, 120.36, 134.9,  140.56, 120.33, 93.27,  64.53, 38.52, 30.09 },
    -- toit maison côté ouest: azimuth 100, pente 32 degrés
    west =  { 28.59, 42.85, 75.18,  97.02,  111.16, 125.59, 131.61, 112.85, 85.74,  56.84, 32.17, 23.7  }
}

-- construction de différentes puissances d'installation
local compute_configuration_yield = function(panel_south_, panels_east_, panels_west_)
    local result = { 0,0,0,0,0,0,0,0,0,0,0,0 }

    local append_site = function(kW_per_kWc_, num_panels_)
        for month, efficiency_ in ipairs(kW_per_kWc_) do
            -- print(month, efficiency_)
            local total_kWc = num_panels_ * kWc_per_panel
            -- print(month, result[i], efficiency_, total_kWc)
            result[month] = result[month] + efficiency_ * total_kWc
        end
    end
    append_site(kW_per_kWc.south, panel_south_)
    append_site(kW_per_kWc.east, panels_east_)
    append_site(kW_per_kWc.west, panels_west_)
	result.yield = (panel_south_ + panels_east_ + panels_west_) * kWc_per_panel * 1000
	result.name = "abri voiture: "..panel_south_.." pan est: "..panels_east_.." pan ouest: "..panels_west_ .. " puissance " .. result.yield / 1000 .. " kWc"
    return make_line(result, true)
end

-- différentes configurations à tester
local Configuration_descriptions =
{
    compute_configuration_yield( 0, 0, 0), -- 0kWc
    compute_configuration_yield( 8, 0, 0), -- 3kWc
    -- compute_configuration_yield( 9, 4, 0), 
	compute_configuration_yield( 8, 8, 0), -- 6kWc
    -- compute_configuration_yield( 9, 12, 0),
    compute_configuration_yield( 8, 12, 4), -- 9kWc
    -- compute_configuration_yield( 9, 15, 0),
    -- compute_configuration_yield( 1000, 0, 0), -- for fun
    -- compute_configuration_yield( 30000, 0, 0),
}

print ""
print "kWh produits par mois"
for configuration, configuration_description in ipairs(Configuration_descriptions) do
	print( configuration_names[configuration], ":", configuration_description.name)
end

display_2d_table{Configuration_descriptions, line_names = configuration_names, column_names = month_names}

---------------------------------------------------------------------------------------------------

-- différence entre la consommation et la production
do
	local compute_configuration_extra_production = function(configuration_description_)
		local result = { 0,0,0,0,0,0,0,0,0,0,0,0 }
		for month, monthly_production in ipairs(configuration_description_) do
			result[month] = monthly_production - Monthly_kW_consumption[month]
		end
		configuration_description_.extra_production = make_line(result, true)
		return result
	end

	local configuration_extra_productions = {}
	for configuration, configuration_description in ipairs(Configuration_descriptions) do
		local configuration_extra_production = compute_configuration_extra_production(configuration_description)
		table.insert(configuration_extra_productions, configuration_extra_production)
	end

	print ""
	print "production - consommation. >0: surproduction. <0: surconsommation"
	display_2d_table{configuration_extra_productions, line_names = configuration_names, column_names = month_names}
end

---------------------------------------------------------------------------------------------------

local simulate_scenario = function(provider_, configuration_)
    -- on liste les mois de surproduction en partant du premier ...
    local sorted_months = {}
    local last_surproduction_month
    for month, production_minus_consumption in ipairs(configuration_.extra_production) do
        if production_minus_consumption > 0 then
            table.insert(sorted_months, month)
            last_surproduction_month = month
        end
    end

	if last_surproduction_month then
		-- ... et les mois de surconsommation
		-- depuis le premier mois de sous-production jusqu'à la fin de l'année ...
		for month = last_surproduction_month+1, 12 do
			assert(configuration_.extra_production[month] <= 0)
			table.insert(sorted_months, month)
		end
		-- ... et on finit avec le début de l'année jusqu'à la fin de la période de sous-production
		for month, self_consumption in ipairs(configuration_.extra_production) do
			if self_consumption > 0 then
				break
			end
			table.insert(sorted_months, month)
		end
	else
		-- aucune surproduction, l'ordre importe peu
		sorted_months = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
	end

    -- un peu de debug display
    -- print ""
    -- print "mois en surproduction"
    -- display_2d_table{{make_line(surproduction_months)}, format = "%d"}
    -- print "mois en surconsommation"
    -- display_2d_table{{make_line(subproduction_months)}, format = "%d"}

    -- on commence la simulation au premier mois de surproduction:
    -- du producteur au consommateur
    local direct_consumed = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)
    -- batterie physique
    local physical_battery_stored = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)
    local physical_battery_consumed = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)
    -- batterie virtuelle
    local virtual_battery_stored = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)
    local virtual_battery_consumed = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)
    -- réseau
    local grid_stored = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)
    local grid_consumed_HC = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)
    local grid_consumed_HP = make_line({0,0,0,0,0,0,0,0,0,0,0,0}, true)

    -- quand on démarre, la batterie est vide, on n'a rien stocké ni soutiré, l'autoconsommation est nulle
    local physical_battery_remaining_capacity = provider_.physical_battery_capacity
    local physical_battery_current_charge = 0
	local peak_physical_battery_charge = 0
    local virtual_battery_remaining_capacity = provider_.virtual_battery_capacity
    local virtual_battery_current_charge = 0
	local peak_virtual_battery_charge = 0
	local generated_kWh = configuration_ -- un alias pour faciliter la lecture du code

	local simulate_one_day = function(month_, daily_production_, daily_daytime_consumption_, daily_nighttime_consumption_)
		local simulate_production = function(remaining_production_)
			if remaining_production_ <= 0 then
				return
			end
			
			-- pendant le jour, l'excédent non consommé est stocké et/ou envoyé sur le réseau
			-- on commence par charger la batterie physique
			if physical_battery_remaining_capacity > remaining_production_ then
				-- la batterie physique peut contenir toute la surproduction de la journée
				physical_battery_stored[month_] = physical_battery_stored[month_] + remaining_production_
				-- toute la surproduction est stockée dans la batterie
				physical_battery_remaining_capacity = physical_battery_remaining_capacity - remaining_production_
				physical_battery_current_charge = physical_battery_current_charge + remaining_production_
				peak_physical_battery_charge = math.max(peak_physical_battery_charge, physical_battery_current_charge)
				-- toute la production est traitée
				return
			end
			
			-- la batterie physique ne peut pas contenir tout l'excédent: on la sature
			physical_battery_stored[month_] = physical_battery_stored[month_] + physical_battery_remaining_capacity
			-- une partie de la production reste à traiter
			remaining_production_ = remaining_production_ - physical_battery_remaining_capacity
			-- la batterie est pleine
			physical_battery_remaining_capacity = 0
			physical_battery_current_charge = provider_.physical_battery_capacity
			peak_physical_battery_charge = math.max(peak_physical_battery_charge, physical_battery_current_charge)
			
			assert(remaining_production_ > 0)
			-- on continue avec la batterie virtuelle si nécessaire
			
			if virtual_battery_remaining_capacity > remaining_production_ then
				-- la batterie physique peut contenir toute la surproduction de la journée
				virtual_battery_stored[month_] = virtual_battery_stored[month_] + remaining_production_
				-- toute la surproduction est stockée dans la batterie
				virtual_battery_remaining_capacity = virtual_battery_remaining_capacity - remaining_production_
				virtual_battery_current_charge = virtual_battery_current_charge + remaining_production_
				peak_virtual_battery_charge = math.max(peak_virtual_battery_charge, virtual_battery_current_charge)
				-- toute la production est traitée
				return
			end
			
			-- la batterie virtuelle ne peut pas contenir tout l'excédent: on la sature
			virtual_battery_stored[month_] = virtual_battery_stored[month_] + virtual_battery_remaining_capacity
			-- le reliquat est envoyé sur le réseau
			grid_stored[month_] = grid_stored[month_] + remaining_production_ - virtual_battery_remaining_capacity
			-- la batterie est pleine
			virtual_battery_remaining_capacity = 0
			virtual_battery_current_charge = provider_.virtual_battery_capacity
			peak_virtual_battery_charge = math.max(peak_virtual_battery_charge, virtual_battery_current_charge)
		end
		
		local simulate_consumption = function(remaining_consumption_)
			-- pendant la nuit, rien ne provient de l'installation
			if remaining_consumption_ <= 0 then
				return
			end
			
			-- on prend ce qu'on peut dans la batterie physique
			if physical_battery_current_charge > remaining_consumption_ then
				-- la batterie physique peut supporter la surconsommation
				physical_battery_current_charge = physical_battery_current_charge - remaining_consumption_
				physical_battery_remaining_capacity = physical_battery_remaining_capacity + remaining_consumption_
				physical_battery_consumed[month_] = physical_battery_consumed[month_] + remaining_consumption_
				-- toute la consommation est traitée
				return
			end

			-- la batterie physique ne couvre pas la surconsommation
			-- on consomme ce qui reste dans la batterie
			physical_battery_consumed[month_] = physical_battery_consumed[month_] + physical_battery_current_charge
			remaining_consumption_ = remaining_consumption_ - physical_battery_current_charge
			-- la batterie physique est vide
			physical_battery_remaining_capacity = provider_.physical_battery_capacity
			physical_battery_current_charge = 0
		
			  -- le reste des besoins est couvert par la batterie virtuelle et le réseau
			if virtual_battery_current_charge > remaining_consumption_ then
				-- la batterie peut supporter la surconsommation
				virtual_battery_current_charge = virtual_battery_current_charge - remaining_consumption_
				virtual_battery_remaining_capacity = virtual_battery_remaining_capacity + remaining_consumption_
				virtual_battery_consumed[month_] = virtual_battery_consumed[month_] + remaining_consumption_
				-- toute la consommation est traitée
				return
			end

			-- la batterie ne couvre pas la surconsommation
			-- on consomme ce qui reste dans la batterie
			virtual_battery_consumed[month_] = virtual_battery_consumed[month_] + virtual_battery_current_charge
			-- le reste est tiré du réseau
			local consumed = remaining_consumption_ - virtual_battery_current_charge
			grid_consumed_HC[month_] = grid_consumed_HC[month_] + consumed * HC_ratios[month_]
			grid_consumed_HP[month_] = grid_consumed_HP[month_] + consumed * (1 - HC_ratios[month_])
			virtual_battery_remaining_capacity = provider_.virtual_battery_capacity
			virtual_battery_current_charge = 0
		end
		
		local remaining_consumption = daily_daytime_consumption_ + daily_nighttime_consumption_
		local remaining_production = daily_production_
		
		-- consommation directe. note: on peut avoir une sous-production sur 24h mais une surproduction pendant le jour!
		local immediate_consumption = math.min(daily_daytime_consumption_, daily_production_)
		direct_consumed[month_] = direct_consumed[month_] + immediate_consumption
		remaining_production = remaining_production - immediate_consumption
		remaining_consumption = remaining_consumption - immediate_consumption
		
		-- stockage de l'excédent de production
		if remaining_production > 0 then
			simulate_production(remaining_production)
		end
		-- soutirage de l'excédent de consommation
		if remaining_consumption > 0 then
			simulate_consumption(remaining_consumption)
		end
	end -- simulate_one_day
	
	-- pendant les mois de sur-production
    for _, month in ipairs(sorted_months) do
        -- statistiques quotidiennes de production et consommation pour le mois en cours
        local daily_consumption = Monthly_kW_consumption[month] / Num_days_per_month[month]
        local daily_daytime_consumption = daily_consumption * Monthly_daytime_ratios[month]
        local daily_nighttime_consumption = daily_consumption * Monthly_nighttime_ratios[month]
        local daily_production = generated_kWh[month] / Num_days_per_month[month]
        local daily_daytime_surproduction = daily_production - daily_daytime_consumption
		
        -- simulation du mois en cours, jour par jour
        for day = 1, Num_days_per_month[month] do
			simulate_one_day(month, daily_production, daily_daytime_consumption, daily_nighttime_consumption)
		end
    end

	return
	{
		direct_consumed = direct_consumed,
		physical_battery_stored = physical_battery_stored,
		physical_battery_consumed = physical_battery_consumed,
		virtual_battery_stored = virtual_battery_stored,
		virtual_battery_consumed = virtual_battery_consumed,
		grid_stored = grid_stored,
		grid_consumed_HC = grid_consumed_HC,
		grid_consumed_HP = grid_consumed_HP,
		peak_physical_battery_charge = peak_physical_battery_charge,
		peak_virtual_battery_charge = peak_virtual_battery_charge,
	}
end -- simulate_scenario

---------------------------------------------------------------------------------------------------

local providers =
{
    {
        name = "EDF OA Base sans batterie physique, tarif base",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 14.78,
            price_per_kWh_HC = 0.1740,
            price_per_kWh_HP = 0.1740,
            price_per_kWh_OA = 0.1,
            price_per_kW_sent_to_virtual_battery = 0,
            price_per_kW_pulled_from_virtual_battery = 0,
            TURPE = 23,
			-- technical part
            physical_battery_capacity = 0,
            physical_battery_cost = 0,
            virtual_battery_capacity = 0,
            virtual_battery_monthly_subscription = 0
        }
    },
    {
        name = "EDF OA Base sans batterie physique, tarif HC",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 15.3,
            price_per_kWh_HC = 0.1841,
            price_per_kWh_HP = 0.1470,
            price_per_kWh_OA = 0.1,
            price_per_kW_sent_to_virtual_battery = 0,
            price_per_kW_pulled_from_virtual_battery = 0,
            TURPE = 23,
			-- technical part
            physical_battery_capacity = 0,
            physical_battery_cost = 0,
            virtual_battery_capacity = 0,
            virtual_battery_monthly_subscription = 0
        }
    },
    {
        name = "EDF OA Base avec batterie physique, tarif HC",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 15.3,
            price_per_kWh_HC = 0.1841,
            price_per_kWh_HP = 0.1470,
            price_per_kWh_OA = 0.1,
            price_per_kW_sent_to_virtual_battery = 0,
            price_per_kW_pulled_from_virtual_battery = 0,
            TURPE = 23,
			-- technical part
            physical_battery_capacity = 10,
            physical_battery_cost = 6000,
            virtual_battery_capacity = 0,
            virtual_battery_monthly_subscription = 0,
        }
    },
    {
        name = "MyLight 100kWh",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 15.3,
            price_per_kWh_HC = 0.1841,
            price_per_kWh_HP = 0.1470,
            price_per_kWh_OA = 0,
            price_per_kW_sent_to_virtual_battery = 0,
            price_per_kW_pulled_from_virtual_battery = 0,
            TURPE = 0,
			-- technical part
            physical_battery_capacity = 0,
            physical_battery_cost = 0,
            virtual_battery_capacity = 100,
            virtual_battery_monthly_subscription = 15,
        }
    },
    {
        name = "MyLight 100kWh avec batterie physique",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 15.3,
            price_per_kWh_HC = 0.1841,
            price_per_kWh_HP = 0.1470,
            price_per_kWh_OA = 0,
            price_per_kW_sent_to_virtual_battery = 0,
            price_per_kW_pulled_from_virtual_battery = 0,
            TURPE = 0,
			-- technical part
            physical_battery_capacity = 10,
            physical_battery_cost = 0,
            virtual_battery_capacity = 100,
            virtual_battery_monthly_subscription = 15,
        }
    },
    {
        name = "MyLight 900kWh",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 15.3,
            price_per_kWh_HC = 0.1841,
            price_per_kWh_HP = 0.1470,
            price_per_kWh_OA = 0,
            price_per_kW_sent_to_virtual_battery = 0,
            price_per_kW_pulled_from_virtual_battery = 0,
            TURPE = 0,
			-- technical part
            physical_battery_capacity = 0,
            physical_battery_cost = 0,
            virtual_battery_capacity = 900,
            virtual_battery_monthly_subscription = 35,
        }
    },
    {
        name = "MyLight 1800kWh",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 15.3,
            price_per_kWh_HC = 0.1841,
            price_per_kWh_HP = 0.1470,
            price_per_kWh_OA = 0,
            price_per_kW_sent_to_virtual_battery = 0,
            price_per_kW_pulled_from_virtual_battery = 0,
            TURPE = 0,
			-- technical part
            physical_battery_capacity = 0,
            physical_battery_cost = 0,
            virtual_battery_capacity = 1800,
            virtual_battery_monthly_subscription = 50,
        }
    },
	{
        name = "UrbanSolarPower",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 18.67,
            price_per_kWh_HC = 0.1992,
            price_per_kWh_HP = 0.4414,
            price_per_kWh_OA = 0,
            price_per_kW_sent_to_virtual_battery = 0.03,
            price_per_kW_pulled_from_virtual_battery = 0.04,
            TURPE = 0,
			-- technical part
            physical_battery_capacity = 0,
            physical_battery_cost = 0,
            virtual_battery_capacity = 1e6,
            virtual_battery_monthly_subscription = function(configuration_) return math.ceil(configuration_.yield / 1000) end,
        }
    },
	{
        name = "UrbanSolarPower avec batterie physique",
        parameters =
        {
			-- cost part
            base_monthly_subscription = 18.67,
            price_per_kWh_HC = 0.1992,
            price_per_kWh_HP = 0.4414,
            price_per_kWh_OA = 0,
            price_per_kW_sent_to_virtual_battery = 0.03,
            price_per_kW_pulled_from_virtual_battery = 0.04,
            TURPE = 0,
			-- technical part
            physical_battery_capacity = 10,
            physical_battery_cost = 5000,
            virtual_battery_capacity = 1e6,
            virtual_battery_monthly_subscription = function(configuration_) return math.ceil(configuration_.yield / 1000) end,
        }
    }
}

---------------------------------------------------------------------------------------------------
-- on mouline toutes les permutations de configuration technique et de fournisseur d'énergie
---------------------------------------------------------------------------------------------------

for _, inflation in ipairs { 1, 2 } do
	print "####################################################################################################"
	print ("inflation: " .. inflation)
	print "####################################################################################################"
	local scenario_names = {}
	local scenario_tags = {}
	local aggregate_direct_consumed = {}
	local aggregate_physical_battery_stored = {}
	local aggregate_physical_battery_consumed = {}
	local aggregate_virtual_battery_stored = {}
	local aggregate_virtual_battery_consumed = {}
	local aggregate_grid_stored = {}
	local aggregate_grid_consumed_HC = {}
	local aggregate_grid_consumed_HP = {}
	local annual_costs = make_line({}, false)
	local peak_virtual_battery_charges = make_line({}, false)
	local annual_productions = make_line({}, false)
	for configuration, configuration_description in ipairs(Configuration_descriptions) do
		for provider, provider_description in ipairs(providers) do
			local scenario_name = provider_description.name .. "  /  " .. configuration_description.name
			-- print ""
			-- print "----------------------------------------------------------------------------------------"
			-- print(scenario_name)
			-- print "----------------------------------------------------------------------------------------"
			table.insert(scenario_names, scenario_name)
			table.insert(scenario_tags, configuration_names[configuration] .. provider)
			
			local statistics = simulate_scenario(provider_description.parameters, configuration_description)
			table.insert(aggregate_direct_consumed, statistics.direct_consumed)
			table.insert(aggregate_physical_battery_stored, statistics.physical_battery_stored)
			table.insert(aggregate_physical_battery_consumed, statistics.physical_battery_stored)
			table.insert(aggregate_virtual_battery_stored, statistics.virtual_battery_stored)
			table.insert(aggregate_virtual_battery_consumed, statistics.virtual_battery_consumed)
			table.insert(aggregate_grid_stored, statistics.grid_stored)
			table.insert(aggregate_grid_consumed_HC, statistics.grid_consumed_HC)
			table.insert(aggregate_grid_consumed_HP, statistics.grid_consumed_HP)
			table.insert(annual_productions, configuration_description.total())
			
			-- partie financière
			local desc = provider_description.parameters
			-- abonnement fixe: base énergie + base batterie virtuelle
			local virtual_battery_monthly_subscription = type(desc.virtual_battery_monthly_subscription) == "function" and desc.virtual_battery_monthly_subscription(configuration_description) or desc.virtual_battery_monthly_subscription
			local subscription_cost = desc.base_monthly_subscription * 12 + virtual_battery_monthly_subscription * 12 + desc.TURPE
			-- partie variable de la batterie virtuelle
			local virtual_battery_cost = statistics.virtual_battery_stored.total() * desc.price_per_kW_sent_to_virtual_battery + statistics.virtual_battery_consumed.total() * desc.price_per_kW_pulled_from_virtual_battery
			table.insert(peak_virtual_battery_charges, statistics.peak_virtual_battery_charge)
			-- énergie non produite
			local grid_consumed_cost = statistics.grid_consumed_HC.total() * desc.price_per_kWh_HC + statistics.grid_consumed_HP.total() * desc.price_per_kWh_HP
			-- total
			local total_cost = subscription_cost + (virtual_battery_cost + grid_consumed_cost) * inflation - statistics.grid_stored.total() * desc.price_per_kWh_OA
			table.insert(annual_costs, total_cost)
		end -- provider
    end -- configuration

	-- rappel de tous les noms des différentes permutations
	print ""
	for scenario, scenario_name in ipairs(scenario_names) do
		print( scenario_tags[scenario], ":", scenario_name)
	end

	-- on affiche les résultats bruts pour comparaison
	local produced_consumption_percentages = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(produced_consumption_percentages, annual_productions[scenario] ~= 0 and 100 * (aggregate_direct_consumed[scenario].total() + aggregate_physical_battery_consumed[scenario].total()) / annual_productions[scenario] or 0)
	end
	print "pourcentage de la production auto-consommée sans passer par le réseau (avec batterie physique le cas échéant)"
	display_2d_table{{produced_consumption_percentages}, column_names = scenario_tags}
	
	local virtual_produced_consumption_percentages = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(virtual_produced_consumption_percentages, annual_productions[scenario] ~= 0 and 100 * (aggregate_direct_consumed[scenario].total() + aggregate_physical_battery_consumed[scenario].total() + aggregate_virtual_battery_consumed[scenario].total()) / annual_productions[scenario] or 0)
	end
	print "pourcentage de la production auto-consommée virtuelle totale (avec prise en compte de la batterie physique et de la batterie virtuelle)"
	display_2d_table{{virtual_produced_consumption_percentages}, column_names = scenario_tags}
	
	local local_self_consumption_percentages = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(local_self_consumption_percentages, 100 * (aggregate_direct_consumed[scenario].total() + aggregate_physical_battery_consumed[scenario].total()) / Monthly_kW_consumption.total())
	end
	print "pourcentage de la consommation totale avec batterie physique (sans sortir de l'installation physique)"
	display_2d_table{{local_self_consumption_percentages}, column_names = scenario_tags}

	local immediate_consumption_percentages = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(immediate_consumption_percentages, 100 * (aggregate_direct_consumed[scenario].total() + aggregate_physical_battery_consumed[scenario].total() + aggregate_virtual_battery_consumed[scenario].total()) / Monthly_kW_consumption.total())
	end
	print "pourcentage de la consommation non facturée au prix du kWh"
	display_2d_table{{immediate_consumption_percentages}, column_names = scenario_tags}

	-- total de chargement de la batterie physique
	local total_physical_battery_stored = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(total_physical_battery_stored, aggregate_physical_battery_stored[scenario].total())
	end
	print "cumul de stockage dans la batterie physique"
	display_2d_table{{total_physical_battery_stored}, column_names = scenario_tags}

	-- total de décharge de la batterie physique
	local total_physical_battery_consumed = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(total_physical_battery_consumed, aggregate_physical_battery_consumed[scenario].total())
	end
	print "cumul de décharge de la batterie physique"
	display_2d_table{{total_physical_battery_consumed}, column_names = scenario_tags}
	
	-- pic d'utilisation de la batterie virtuelle
	local peak_virtual_battery_charge = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(peak_virtual_battery_charge, aggregate_virtual_battery_stored[scenario].total())
	end
	print "pic de remplissage batterie virtuelle"
	display_2d_table{{peak_virtual_battery_charges}, column_names = scenario_tags}

	-- total d'utilisation de la batterie virtuelle
	local total_virtual_battery_stored = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(total_virtual_battery_stored, aggregate_virtual_battery_stored[scenario].total())
	end
	print "cumul de stockage dans la batterie virtuelle"
	display_2d_table{{total_virtual_battery_stored}, column_names = scenario_tags}
	
	-- total de décharge de la batterie virtuelle
	local total_virtual_battery_consumed = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		table.insert(total_virtual_battery_consumed, aggregate_virtual_battery_consumed[scenario].total())
	end
	print "cumul de décharge de la batterie virtuelle"
	display_2d_table{{total_virtual_battery_consumed}, column_names = scenario_tags}

	-- partie financière (la seule qui change en fonction de l'inflation, évidemment)
	print "facture annuelle: abonnement fournisseur + abonnement batterie + TURPE + quantité soutirée - quantité revendue"
	display_2d_table{{annual_costs}, column_names = scenario_tags}

	-- ce qu'on aurait payé si on ne change rien (situation EDF Tarif base)
	local raw_cost = 14.78 * 12 + Monthly_kW_consumption.total() * 0.1740 * inflation
	
	local annual_savings = make_line({}, false)
	for scenario, scenario_name in ipairs(scenario_names) do
		-- économie: facture originale - facture avec installation photovoltaïque
		table.insert(annual_savings, raw_cost - annual_costs[scenario])
	end
	print("économie (facture estimée sans rien changer " .. raw_cost .. ")")
	display_2d_table{{annual_savings}, column_names = scenario_tags}
end -- inflation

