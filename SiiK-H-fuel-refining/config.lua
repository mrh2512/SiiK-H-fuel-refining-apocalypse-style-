Config = {}

Config.Target = 'qb-target' -- 'qb-target' or 'ox_target'
Config.TargetDistance = 2.2

-- Models
Config.PumpjackModel = `p_oil_pjack_02_s`
Config.RefineryModel = `prop_byard_machine02`
Config.DrumModel     = `prop_air_fueltrail1`

-- Items
Config.CrudeItem        = 'crude_oil'
Config.RefinedFuelItem  = 'refined_fuel'
Config.EmptyJerrycan    = 'empty_jerrycan'
Config.FuelJerrycan     = 'fuel_jerrycan'

Config.DrumKitItem      = 'oil_drum_kit'
Config.RefineryKitItem  = 'refinery_kit'
Config.PumpjackKitItem  = 'pumpjack_kit'

-- Pumpjack rewards
Config.PumpjackReward = {
  item = 'crude_oil',
  min = 1,
  max = 2
}

-- Refinery recipe
Config.Refine = {
  InputItem = 'crude_oil',
  InputAmount = 3,
  OutputItem = 'refined_fuel',
  OutputAmount = 1,
}

-- Drum logic (SQL levels)
Config.Drum = {
  DefaultMax = 100.0,
  DefaultStart = 50.0,

  AddPerRefinedFuel = 25.0,
  DrainPerJerrycan  = 25.0,

  InteractFindRadius = 3.0,
  Place = { PreviewDistance=6.0, RotateStep=5.0, TooCloseDist=2.0 }
}

Config.RefineryPlace = { PreviewDistance=6.0, RotateStep=5.0, TooCloseDist=3.0, InteractFindRadius=4.0 }
Config.PumpjackPlace = { PreviewDistance=6.0, RotateStep=5.0, TooCloseDist=3.0, InteractFindRadius=4.0 }

-- Skillbars
Config.SkillbarPump   = { rounds = 2, durationMin = 800, durationMax = 1200 }
Config.SkillbarRefine = { rounds = 2, durationMin = 800, durationMax = 1200 }
Config.SkillbarFill   = { rounds = 1, durationMin = 800, durationMax = 1200 }
Config.SkillbarPour   = { rounds = 1, durationMin = 800, durationMax = 1200 }

-- Target labels/icons
Config.TargetPumpLabel     = 'Operate Pumpjack'
Config.TargetPumpIcon      = 'fas fa-industry'
Config.TargetRefineryLabel = 'Use Refinery'
Config.TargetRefineryIcon  = 'fas fa-oil-can'
Config.TargetDrumLabel     = 'Fuel Drum'
Config.TargetDrumIcon      = 'fas fa-fill-drip'

-- Vehicle fuel system (qb-hud compatible)
Config.VehicleFuel = {
  Enabled = true,
  TickMs = 1200,
  Min = 0.0,
  Max = 100.0,

  BaseDrain   = 0.020,
  RpmFactor   = 0.060,
  SpeedFactor = 0.010,

  -- Option B: charged jerrycan
  JerrycanMax  = 25.0,
  RefuelAmount = 25.0, -- cap per use

  StateKey = 'siik_fuel_level',

  ClassMultiplier = {
    [0]=1.00,[1]=1.02,[2]=1.05,[3]=1.03,[4]=1.08,[5]=1.10,[6]=1.12,[7]=1.20,
    [8]=0.80,[9]=1.10,[10]=1.25,[11]=1.15,[12]=1.12,[13]=0.0,[14]=0.0,
    [15]=0.0,[16]=0.0,[17]=1.10,[18]=1.15,[19]=1.35,[20]=1.40,[21]=0.0,
  }
}

-- Placement Restrictions (client + server)
Config.Placement = {
  Enabled = true,
  RequireAllowedZone = true,

  AllowedZones = {
    { name="Oil Fields (Grapeseed)", coords={x=2578.2,y=3002.7,z=43.9}, radius=600.0 },
    { name="Davis Quartz",          coords={x=2709.9,y=2774.2,z=37.9}, radius=450.0 },
    { name="LS Docks Industrial",   coords={x= 966.5,y=-3006.2,z= 5.9}, radius=650.0 },
    { name="East LS Industrial",    coords={x= 874.2,y=-2100.1,z=30.5}, radius=500.0 },
  },

  BlockedZones = {
    { name="Legion Square", coords={x=200.9,y=-923.2,z=30.7}, radius=220.0 },
    { name="Hospital",      coords={x=308.2,y=-585.4,z=43.3}, radius=220.0 },
    { name="MRPD",          coords={x=441.2,y=-982.6,z=30.7}, radius=220.0 },
    { name="Airport",       coords={x=-1034.6,y=-2733.6,z=20.1}, radius=500.0 },
  },

  NoPlacePoints = {}
}
