local _, Addon = ...
Addon.TameableAbilities = {
  ["arcane-resistance"] = { name = "Arcane Resistance", learned_by = {}, passive = true, trainer = true, ranks = {
    { spell_id = 24493, rank = 1, pet_level = 20, training_cost = 5, trainer_cost = 440, learn_id = 24495 },
    { spell_id = 24497, rank = 2, pet_level = 30, training_cost = 15, trainer_cost = 1600, learn_id = 24508 },
    { spell_id = 24500, rank = 3, pet_level = 40, training_cost = 45, trainer_cost = 3600, learn_id = 24509 },
    { spell_id = 24501, rank = 4, pet_level = 50, training_cost = 90, trainer_cost = 7200, learn_id = 24510 }
  } },
  ["bite"] = { name = "Bite", learned_by = { "Bat", "Bear", "Boar", "Carrion Bird", "Cat", "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf" }, ranks = {
    { spell_id = 17253, rank = 1, pet_level = 1, training_cost = 1, learn_id = 17254, npc_ids = { 1509, 1505, 30, 1688, 1994, 2958, 1138, 250868, 255887, 1131, 1922, 1999, 2959, 266851, 3110 } },
    { spell_id = 17255, rank = 2, pet_level = 8, training_cost = 4, learn_id = 17262, npc_ids = { 1133, 2000, 254589, 118, 1555, 2960, 268530, 834, 1132, 1195, 1765, 2001, 256492, 833, 7319, 1693, 442, 3461, 210107, 270693 } },
    { spell_id = 17256, rank = 3, pet_level = 16, training_cost = 7, learn_id = 17263, npc_ids = { 1923, 4005, 1185, 3823, 5053, 505, 4006, 14266, 2172, 2350, 3653, 569, 11921, 2476, 521, 616, 4824, 14279 } },
    { spell_id = 17257, rank = 4, pet_level = 24, training_cost = 10, learn_id = 17264, npc_ids = { 2349, 628, 1112, 1258, 2089, 4887, 2348, 4825, 574, 3825, 3821, 2408, 14223 } },
    { spell_id = 17258, rank = 5, pet_level = 32, training_cost = 13, learn_id = 17265, npc_ids = { 2563, 4143, 2565, 2727, 4341, 4413, 4396, 4411, 2753, 4344, 4412 } },
    { spell_id = 17259, rank = 6, pet_level = 40, training_cost = 17, learn_id = 17266, npc_ids = { 14233, 769, 4345, 5286, 1087, 4400, 5356, 8211, 4841, 13599, 8762, 8959, 14339 } },
    { spell_id = 17260, rank = 7, pet_level = 48, training_cost = 21, learn_id = 17267, npc_ids = { 8277, 2505, 2681, 3581, 8933, 8213, 8961, 6585, 1817, 1824 } },
    { spell_id = 17261, rank = 8, pet_level = 56, training_cost = 25, learn_id = 17268, npc_ids = { 9696, 11370 } }
  } },
  ["charge"] = { name = "Charge", learned_by = { "Boar" }, unique = true, ranks = {
    { spell_id = 7371, rank = 1, pet_level = 1, training_cost = 5, learn_id = 7370, npc_ids = { 1984, 3098, 1985, 3099, 708, 2966, 2954, 113, 1125, 1126, 390, 524, 1127, 3100, 330, 1689, 119, 1190, 3225 } },
    { spell_id = 26177, rank = 2, pet_level = 12, training_cost = 9, learn_id = 26184, npc_ids = { 454, 157, 1191, 547, 1192 } },
    { spell_id = 26178, rank = 3, pet_level = 24, training_cost = 13, learn_id = 26185, npc_ids = { 345, 4511, 4514, 4512 } },
    { spell_id = 26179, rank = 4, pet_level = 36, training_cost = 17, learn_id = 26186, npc_ids = { 255851 } },
    { spell_id = 26201, rank = 5, pet_level = 48, training_cost = 21, learn_id = 26202, npc_ids = { 5992, 8303 } },
    { spell_id = 27685, rank = 6, pet_level = 60, training_cost = 25, learn_id = 28343, npc_ids = { 16117 } }
  } },
  ["claw"] = { name = "Claw", learned_by = { "Bear", "Bird of Prey", "Carrion Bird", "Cat", "Crab", "Raptor", "Scorpid" }, ranks = {
    { spell_id = 16827, rank = 1, pet_level = 1, training_cost = 1, learn_id = 2980, npc_ids = { 3124, 250926, 3281, 250937, 1995, 3106, 251115, 1196, 2970, 250928 } },
    { spell_id = 16828, rank = 2, pet_level = 8, training_cost = 4, learn_id = 2981, npc_ids = { 822, 1997, 254588, 3108, 3127, 250927, 276111, 276189, 1778, 1961, 2163, 5823, 1130, 2232 } },
    { spell_id = 16829, rank = 3, pet_level = 16, training_cost = 7, learn_id = 2982, npc_ids = { 1189, 1216, 6788, 3619, 3812, 1225, 2351, 3809, 4821, 4822 } },
    { spell_id = 16830, rank = 4, pet_level = 24, training_cost = 10, learn_id = 3667, npc_ids = { 3810, 4823, 4140, 4696 } },
    { spell_id = 16831, rank = 5, pet_level = 32, training_cost = 13, learn_id = 2975, npc_ids = { 4697, 5937, 7022 } },
    { spell_id = 16832, rank = 6, pet_level = 40, training_cost = 17, learn_id = 2976, npc_ids = { 5422, 922, 5268, 731, 1088, 5352 } },
    { spell_id = 3010, rank = 7, pet_level = 48, training_cost = 21, learn_id = 2977, npc_ids = { 5274, 8958, 7099, 14344, 14343, 7444, 8301, 7455, 9695, 1816 } },
    { spell_id = 3009, rank = 8, pet_level = 56, training_cost = 25, learn_id = 3666, npc_ids = { 7445, 7456 } }
  } },
  ["cower"] = { name = "Cower", learned_by = {}, ranks = {
    { spell_id = 1742, rank = 1, pet_level = 5, training_cost = 8, learn_id = 1747, npc_ids = { 1199, 1553, 2042, 251245, 3035, 3121, 2957, 253282, 3068, 276198, 2070, 2321, 3246 } },
    { spell_id = 1753, rank = 2, pet_level = 15, training_cost = 10, learn_id = 1748, npc_ids = { 3245, 2237, 2323, 2384, 4067 } },
    { spell_id = 1754, rank = 3, pet_level = 25, training_cost = 12, learn_id = 1749, npc_ids = { 4126, 2385, 681, 683, 4538, 736, 4425, 4539 } },
    { spell_id = 1755, rank = 4, pet_level = 35, training_cost = 14, learn_id = 1750, npc_ids = { 3241, 2731, 4725, 2732, 4861 } },
    { spell_id = 1756, rank = 5, pet_level = 45, training_cost = 16, learn_id = 1751, npc_ids = { 2522, 8927, 8600, 8601 } },
    { spell_id = 16697, rank = 6, pet_level = 55, training_cost = 18, learn_id = 16698, npc_ids = { 7430, 8602 } }
  } },
  ["dash"] = { name = "Dash", learned_by = { "Bear", "Boar", "Cat", "Crab", "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle", "Wolf" }, ranks = {
    { spell_id = 23099, rank = 1, pet_level = 30, training_cost = 15, learn_id = 23100, npc_ids = { 4724, 682, 976, 4304, 4688, 2727, 4950, 767, 729, 2728, 2850, 4662, 4725, 2729 } },
    { spell_id = 23109, rank = 2, pet_level = 40, training_cost = 20, learn_id = 23111, npc_ids = { 5425, 728, 2734, 5286, 263315, 1713, 2730, 8211, 8208, 5426, 2926, 5427 } },
    { spell_id = 23110, rank = 3, pet_level = 50, training_cost = 25, learn_id = 23112, npc_ids = { 2681, 8303, 8300, 9416, 7055, 9696, 10200, 7433, 7432, 11365, 15067 } }
  } },
  ["demoralizing-screech"] = { name = "Demoralizing Screech", learned_by = { "Carrion Bird" }, unique = true, ranks = {
    { spell_id = 24423, rank = 1, pet_level = 8, training_cost = 10, learn_id = 24424, npc_ids = { 2971, 154 } },
    { spell_id = 24577, rank = 2, pet_level = 24, training_cost = 15, learn_id = 24580, npc_ids = { 4158, 4694 } },
    { spell_id = 24578, rank = 3, pet_level = 48, training_cost = 20, learn_id = 24581, npc_ids = { 1809 } },
    { spell_id = 24579, rank = 4, pet_level = 56, training_cost = 25, learn_id = 24582 }
  } },
  ["dismember"] = { name = "Dismember", learned_by = { "Crocolisk" }, unique = true, ranks = {
    { spell_id = 1264758, rank = 1, pet_level = 12, training_cost = 1, learn_id = 1264937, npc_ids = { 1693, 270693 } },
    { spell_id = 1264927, rank = 2, pet_level = 24, training_cost = 1, learn_id = 1264939, npc_ids = { 1150 } },
    { spell_id = 1264929, rank = 3, pet_level = 36, training_cost = 1, learn_id = 1264970, npc_ids = { 259046 } },
    { spell_id = 1264930, rank = 4, pet_level = 48, training_cost = 1, learn_id = 1264971 },
    { spell_id = 1264933, rank = 5, pet_level = 60, training_cost = 1, learn_id = 1264972 }
  } },
  ["dive"] = { name = "Dive", learned_by = { "Bat", "Bird of Prey", "Carrion Bird", "Wind Serpent" }, ranks = {
    { spell_id = 23145, rank = 1, pet_level = 30, training_cost = 15, learn_id = 23146, npc_ids = { 4538, 2578, 4425, 4539, 2579, 6013, 4693, 4861, 4346, 4347, 4348 } },
    { spell_id = 23147, rank = 2, pet_level = 40, training_cost = 20, learn_id = 23149, npc_ids = { 5307, 5428, 5429, 5308, 8207, 5430, 7097, 5349 } },
    { spell_id = 23148, rank = 3, pet_level = 50, training_cost = 25, learn_id = 23150, npc_ids = { 1809, 5708, 7099, 8927, 7098, 8299, 14343, 8600, 7455, 2931 } }
  } },
  ["dust-cloud"] = { name = "Dust Cloud", learned_by = { "Tallstrider" }, unique = true, ranks = {
    { spell_id = 1265899, rank = 1, pet_level = 12, training_cost = 0, learn_id = 1265907, npc_ids = { 3246, 2172 } },
    { spell_id = 1265901, rank = 2, pet_level = 24, training_cost = 0, learn_id = 1265908, npc_ids = { 4724 } },
    { spell_id = 1265902, rank = 3, pet_level = 36, training_cost = 0, learn_id = 1265909, npc_ids = { 4725 } },
    { spell_id = 1265903, rank = 4, pet_level = 48, training_cost = 0, learn_id = 1265913 },
    { spell_id = 1265904, rank = 5, pet_level = 60, training_cost = 0, learn_id = 1265911 }
  } },
  ["fire-resistance"] = { name = "Fire Resistance", learned_by = {}, passive = true, trainer = true, ranks = {
    { spell_id = 23992, rank = 1, pet_level = 20, training_cost = 5, trainer_cost = 440, learn_id = 24440 },
    { spell_id = 24439, rank = 2, pet_level = 30, training_cost = 15, trainer_cost = 1600, learn_id = 24441 },
    { spell_id = 24444, rank = 3, pet_level = 40, training_cost = 45, trainer_cost = 3600, learn_id = 24463 },
    { spell_id = 24445, rank = 4, pet_level = 50, training_cost = 90, trainer_cost = 7200, learn_id = 24464 }
  } },
  ["frost-resistance"] = { name = "Frost Resistance", learned_by = {}, passive = true, trainer = true, ranks = {
    { spell_id = 24446, rank = 1, pet_level = 20, training_cost = 5, trainer_cost = 440, learn_id = 24475 },
    { spell_id = 24447, rank = 2, pet_level = 30, training_cost = 15, trainer_cost = 1600, learn_id = 24476 },
    { spell_id = 24448, rank = 3, pet_level = 40, training_cost = 45, trainer_cost = 3600, learn_id = 24477 },
    { spell_id = 24449, rank = 4, pet_level = 50, training_cost = 90, trainer_cost = 7200, learn_id = 24478 }
  } },
  ["furious-howl"] = { name = "Furious Howl", learned_by = { "Wolf" }, unique = true, ranks = {
    { spell_id = 24604, rank = 1, pet_level = 10, training_cost = 10, learn_id = 24609, npc_ids = { 1765, 833, 274300, 12431, 10644 } },
    { spell_id = 24605, rank = 2, pet_level = 24, training_cost = 15, learn_id = 24608, npc_ids = { 1258, 3825, 2729, 2925 } },
    { spell_id = 24603, rank = 3, pet_level = 40, training_cost = 20, learn_id = 24607, npc_ids = { 5286, 5356, 2924, 5287, 8959, 14339 } },
    { spell_id = 24597, rank = 4, pet_level = 56, training_cost = 25, learn_id = 24599, npc_ids = { 9696 } }
  } },
  ["great-stamina"] = { name = "Great Stamina", learned_by = {}, passive = true, trainer = true, ranks = {
    { spell_id = 4187, rank = 1, pet_level = 1, training_cost = 5, trainer_cost = 10, learn_id = 4195 },
    { spell_id = 4188, rank = 2, pet_level = 12, training_cost = 10, trainer_cost = 120, learn_id = 4196 },
    { spell_id = 4189, rank = 3, pet_level = 18, training_cost = 15, trainer_cost = 400, learn_id = 4197 },
    { spell_id = 4190, rank = 4, pet_level = 24, training_cost = 25, trainer_cost = 1400, learn_id = 4198 },
    { spell_id = 4191, rank = 5, pet_level = 30, training_cost = 50, trainer_cost = 1600, learn_id = 4199 },
    { spell_id = 4192, rank = 6, pet_level = 36, training_cost = 75, trainer_cost = 2800, learn_id = 4200 },
    { spell_id = 4193, rank = 7, pet_level = 42, training_cost = 100, trainer_cost = 4800, learn_id = 4201 },
    { spell_id = 4194, rank = 8, pet_level = 48, training_cost = 125, trainer_cost = 6400, learn_id = 4202 },
    { spell_id = 5041, rank = 9, pet_level = 54, training_cost = 150, trainer_cost = 8400, learn_id = 5048 },
    { spell_id = 5042, rank = 10, pet_level = 60, training_cost = 185, trainer_cost = 10000, learn_id = 5049 }
  } },
  ["growl"] = { name = "Growl", learned_by = {}, trainer = true, ranks = {
    { spell_id = 2649, rank = 1, pet_level = 1, training_cost = 0, learn_id = 1853 },
    { spell_id = 14916, rank = 2, pet_level = 10, training_cost = 0, learn_id = 14922 },
    { spell_id = 14917, rank = 3, pet_level = 20, training_cost = 0, trainer_cost = 440, learn_id = 14923 },
    { spell_id = 14918, rank = 4, pet_level = 30, training_cost = 0, trainer_cost = 1600, learn_id = 14924 },
    { spell_id = 14919, rank = 5, pet_level = 40, training_cost = 0, trainer_cost = 3600, learn_id = 14925 },
    { spell_id = 14920, rank = 6, pet_level = 50, training_cost = 0, trainer_cost = 7200, learn_id = 14926 },
    { spell_id = 14921, rank = 7, pet_level = 60, training_cost = 0, trainer_cost = 10000, learn_id = 14927 }
  } },
  ["lightning-breath"] = { name = "Lightning Breath", learned_by = { "Wind Serpent" }, unique = true, ranks = {
    { spell_id = 24844, rank = 1, pet_level = 1, training_cost = 1, learn_id = 24845 },
    { spell_id = 25008, rank = 2, pet_level = 12, training_cost = 5, learn_id = 25013, npc_ids = { 3630, 3631, 3247, 3424, 5056, 5756, 3249 } },
    { spell_id = 25009, rank = 3, pet_level = 24, training_cost = 10, learn_id = 25014, npc_ids = { 3472, 4117, 4118, 4119 } },
    { spell_id = 25010, rank = 4, pet_level = 36, training_cost = 15, learn_id = 25015, npc_ids = { 5307, 5308, 4347, 4348 } },
    { spell_id = 25011, rank = 5, pet_level = 48, training_cost = 20, learn_id = 25016, npc_ids = { 5291, 5349, 8336, 5708 } },
    { spell_id = 25012, rank = 6, pet_level = 60, training_cost = 25, learn_id = 25017, npc_ids = { 11357, 11359 } }
  } },
  ["mine"] = { name = "Mine!", learned_by = { "Bird of Prey" }, unique = true, ranks = {
    { spell_id = 1265054, rank = 1, pet_level = 10, training_cost = 0, learn_id = 1265059, npc_ids = { 270298, 276101, 270196 } },
    { spell_id = 1265055, rank = 2, pet_level = 20, training_cost = 0, learn_id = 1265060 },
    { spell_id = 1265056, rank = 3, pet_level = 30, training_cost = 0, learn_id = 1265061, npc_ids = { 272389 } },
    { spell_id = 1265057, rank = 4, pet_level = 40, training_cost = 0, learn_id = 1265062 },
    { spell_id = 1265058, rank = 5, pet_level = 50, training_cost = 0, learn_id = 1265064, npc_ids = { 7456 } }
  } },
  ["natural-armor"] = { name = "Natural Armor", learned_by = {}, passive = true, trainer = true, ranks = {
    { spell_id = 24545, rank = 1, pet_level = 1, training_cost = 1, trainer_cost = 10, learn_id = 24547 },
    { spell_id = 24549, rank = 2, pet_level = 12, training_cost = 5, trainer_cost = 120, learn_id = 24556 },
    { spell_id = 24550, rank = 3, pet_level = 18, training_cost = 10, trainer_cost = 400, learn_id = 24557 },
    { spell_id = 24551, rank = 4, pet_level = 24, training_cost = 15, trainer_cost = 1400, learn_id = 24558 },
    { spell_id = 24552, rank = 5, pet_level = 30, training_cost = 25, trainer_cost = 1600, learn_id = 24559 },
    { spell_id = 24553, rank = 6, pet_level = 36, training_cost = 50, trainer_cost = 2800, learn_id = 24560 },
    { spell_id = 24554, rank = 7, pet_level = 42, training_cost = 75, trainer_cost = 4800, learn_id = 24561 },
    { spell_id = 24555, rank = 8, pet_level = 48, training_cost = 100, trainer_cost = 6400, learn_id = 24562 },
    { spell_id = 24629, rank = 9, pet_level = 54, training_cost = 125, trainer_cost = 8400, learn_id = 24631 },
    { spell_id = 24630, rank = 10, pet_level = 60, training_cost = 150, trainer_cost = 10000, learn_id = 24632 }
  } },
  ["nature-resistance"] = { name = "Nature Resistance", learned_by = {}, passive = true, trainer = true, ranks = {
    { spell_id = 24492, rank = 1, pet_level = 20, training_cost = 5, trainer_cost = 440, learn_id = 24494 },
    { spell_id = 24502, rank = 2, pet_level = 30, training_cost = 15, trainer_cost = 1600, learn_id = 24511 },
    { spell_id = 24503, rank = 3, pet_level = 40, training_cost = 45, trainer_cost = 3600, learn_id = 24512 },
    { spell_id = 24504, rank = 4, pet_level = 50, training_cost = 90, trainer_cost = 7200, learn_id = 24513 }
  } },
  ["pinch"] = { name = "Pinch", learned_by = { "Crab" }, unique = true, ranks = {
    { spell_id = 1264735, rank = 1, pet_level = 12, training_cost = 0, learn_id = 1264745, npc_ids = { 1216, 2236 } },
    { spell_id = 1264736, rank = 2, pet_level = 24, training_cost = 0, learn_id = 1264749, npc_ids = { 12347 } },
    { spell_id = 1264739, rank = 3, pet_level = 36, training_cost = 0, learn_id = 1264750 },
    { spell_id = 1264741, rank = 4, pet_level = 48, training_cost = 0, learn_id = 1264751 },
    { spell_id = 1264742, rank = 5, pet_level = 60, training_cost = 0, learn_id = 1264752 }
  } },
  ["prowl"] = { name = "Prowl", learned_by = { "Cat" }, unique = true, ranks = {
    { spell_id = 24450, rank = 1, pet_level = 30, training_cost = 15, learn_id = 24451, npc_ids = { 2406, 2731, 684, 768 } },
    { spell_id = 24452, rank = 2, pet_level = 40, training_cost = 20, learn_id = 24454, npc_ids = { 2734, 1713, 731 } },
    { spell_id = 24453, rank = 3, pet_level = 50, training_cost = 25, learn_id = 24455, npc_ids = { 2522, 7432, 15067 } }
  } },
  ["savage-rend"] = { name = "Savage Rend", learned_by = { "Raptor" }, unique = true, ranks = {
    { spell_id = 1265065, rank = 1, pet_level = 12, training_cost = 0, learn_id = 1265831, npc_ids = { 3255 } },
    { spell_id = 1265066, rank = 2, pet_level = 24, training_cost = 0, learn_id = 1265833, npc_ids = { 1015, 1016, 855 } },
    { spell_id = 1265067, rank = 3, pet_level = 36, training_cost = 0, learn_id = 1265834, npc_ids = { 4355 } },
    { spell_id = 1265068, rank = 4, pet_level = 48, training_cost = 0, learn_id = 1265835 },
    { spell_id = 1265069, rank = 5, pet_level = 60, training_cost = 0, learn_id = 1265836 }
  } },
  ["scorpid-poison"] = { name = "Scorpid Poison", learned_by = { "Scorpid" }, unique = true, ranks = {
    { spell_id = 24640, rank = 1, pet_level = 8, training_cost = 10, learn_id = 24641, npc_ids = { 3127, 3226, 5823, 3250, 3252 } },
    { spell_id = 24583, rank = 2, pet_level = 24, training_cost = 15, learn_id = 24584, npc_ids = { 4140, 4696, 4139, 4697, 5937, 7078, 4699 } },
    { spell_id = 24586, rank = 3, pet_level = 40, training_cost = 20, learn_id = 24588, npc_ids = { 5422, 7405, 5423, 5424, 7803, 5988, 8926, 9691, 9695, 11735 } },
    { spell_id = 24587, rank = 4, pet_level = 56, training_cost = 25, learn_id = 24589, npc_ids = { 9698, 11736, 14476, 11737 } }
  } },
  ["shadow-resistance"] = { name = "Shadow Resistance", learned_by = {}, passive = true, trainer = true, ranks = {
    { spell_id = 24488, rank = 1, pet_level = 20, training_cost = 5, trainer_cost = 440, learn_id = 24490 },
    { spell_id = 24505, rank = 2, pet_level = 30, training_cost = 15, trainer_cost = 1600, learn_id = 24514 },
    { spell_id = 24506, rank = 3, pet_level = 40, training_cost = 45, trainer_cost = 3600, learn_id = 24515 },
    { spell_id = 24507, rank = 4, pet_level = 40, training_cost = 90, trainer_cost = 7200, learn_id = 24516 }
  } },
  ["shell-shield"] = { name = "Shell Shield", learned_by = { "Turtle" }, unique = true, ranks = {
    { spell_id = 26064, rank = 1, pet_level = 20, training_cost = 15, learn_id = 26065, npc_ids = { 3653, 4824, 4887, 4825, 2408, 14223, 8213 } }
  } },
  ["sonic-blast"] = { name = "Sonic Blast", learned_by = { "Bat" }, unique = true, ranks = {
    { spell_id = 1264478, rank = 1, pet_level = 12, training_cost = 1, learn_id = 1264483, npc_ids = { 277882 } },
    { spell_id = 1264479, rank = 2, pet_level = 24, training_cost = 1, learn_id = 1264484, npc_ids = { 277881 } },
    { spell_id = 1264480, rank = 3, pet_level = 36, training_cost = 1, learn_id = 1264486, npc_ids = { 262037 } },
    { spell_id = 1264481, rank = 4, pet_level = 48, training_cost = 1, learn_id = 1264487 },
    { spell_id = 1264482, rank = 5, pet_level = 60, training_cost = 1, learn_id = 1264488 }
  } },
  ["swipe"] = { name = "Swipe", learned_by = { "Bear" }, unique = true, ranks = {
    { spell_id = 1264494, rank = 1, pet_level = 12, training_cost = 0, learn_id = 1264727, npc_ids = { 1797, 1188, 259388 } },
    { spell_id = 1264497, rank = 2, pet_level = 24, training_cost = 0, learn_id = 1264729, npc_ids = { 2356, 271334, 14280 } },
    { spell_id = 1264498, rank = 3, pet_level = 36, training_cost = 0, learn_id = 1264730 },
    { spell_id = 1264501, rank = 4, pet_level = 48, training_cost = 0, learn_id = 1264731 },
    { spell_id = 1264502, rank = 5, pet_level = 60, training_cost = 0, learn_id = 1264732 }
  } },
  ["tendon-rip"] = { name = "Tendon Rip", learned_by = { "Hyena" }, unique = true, ranks = {
    { spell_id = 1265038, rank = 1, pet_level = 12, training_cost = 0, learn_id = 1265043, npc_ids = { 4127, 4129 } },
    { spell_id = 1265039, rank = 2, pet_level = 24, training_cost = 0, learn_id = 1265045, npc_ids = { 4248, 4249 } },
    { spell_id = 1265040, rank = 3, pet_level = 36, training_cost = 0, learn_id = 1265046 },
    { spell_id = 1265041, rank = 4, pet_level = 48, training_cost = 0, learn_id = 1265047 },
    { spell_id = 1265042, rank = 5, pet_level = 60, training_cost = 0, learn_id = 1265048 }
  } },
  ["thunderstomp"] = { name = "Thunderstomp", learned_by = { "Gorilla" }, unique = true, ranks = {
    { spell_id = 26090, rank = 1, pet_level = 30, training_cost = 15, learn_id = 26094, npc_ids = { 1108, 1114 } },
    { spell_id = 26187, rank = 2, pet_level = 40, training_cost = 20, learn_id = 26189, npc_ids = { 1557, 5262 } },
    { spell_id = 26188, rank = 3, pet_level = 50, training_cost = 25, learn_id = 26190, npc_ids = { 6516, 9622 } },
    { spell_id = 1264455, rank = 4, pet_level = 60, training_cost = 0, learn_id = 1264456 }
  } },
  ["tricksters-dance"] = { name = "Trickster's Dance", learned_by = { "Fox" }, unique = true, ranks = {
    { spell_id = 1310612, rank = 1, pet_level = 20, training_cost = 10, learn_id = 1310617, npc_ids = { 250874, 277645 } }
  } },
  ["web"] = { name = "Web", learned_by = { "Spider" }, unique = true, ranks = {
    { spell_id = 1265843, rank = 1, pet_level = 12, training_cost = 0, learn_id = 1265887, npc_ids = { 1780, 1184, 1781, 4263, 4007, 217, 3819, 1111, 4264 } },
    { spell_id = 1265878, rank = 2, pet_level = 24, training_cost = 0, learn_id = 1265888, npc_ids = { 930, 2349, 3820 } },
    { spell_id = 1265880, rank = 3, pet_level = 36, training_cost = 0, learn_id = 1265890 },
    { spell_id = 1265881, rank = 4, pet_level = 48, training_cost = 0, learn_id = 1265891 },
    { spell_id = 1265883, rank = 5, pet_level = 60, training_cost = 0, learn_id = 1265892 }
  } }
}
