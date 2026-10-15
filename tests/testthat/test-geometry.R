test_that("goal distance is measured to the centre of the goal", {
  expect_equal(goal_distance(120, 40), 0)
  expect_equal(goal_distance(108, 40), 12)
  expect_equal(goal_distance(120, 30), 10)
})

test_that("the goalmouth subtends a wider angle from in front than from the side", {
  central <- goal_angle(108, 40)
  wide    <- goal_angle(108, 10)
  expect_gt(central, wide)
})

test_that("angle from the penalty spot matches the geometry", {
  # 12 yards out, dead centre, an 8 yard goal: 2 * atan(4 / 12)
  expect_equal(goal_angle(108, 40), 2 * atan(4 / 12), tolerance = 1e-9)
})

test_that("the shooting cone contains defenders standing in front of goal", {
  expect_true(in_shooting_cone(115, 40, 100, 40))
  expect_false(in_shooting_cone(115, 5, 100, 40))
})

test_that("a defender behind the shooter is not in the cone", {
  expect_false(in_shooting_cone(90, 40, 100, 40))
})

test_that("polygon area handles a known rectangle", {
  square <- cbind(c(0, 10, 10, 0), c(0, 0, 5, 5))
  expect_equal(polygon_area(square), 50)
  expect_equal(polygon_area(square[1:2, ]), 0)
})

test_that("clipping a rectangle in half halves its area", {
  rect <- cbind(c(0, 20, 20, 0), c(0, 0, 10, 10))
  expect_equal(polygon_area(clip_to_halfplane(rect, 10)), 100)
  expect_equal(polygon_area(clip_to_halfplane(rect, 0)), 200)
  expect_equal(nrow(clip_to_halfplane(rect, 25)), 0)
})

test_that("forward visibility is one when the whole forward area is in view", {
  whole <- cbind(c(0, 120, 120, 0), c(0, 0, 80, 80))
  expect_equal(forward_visibility(whole, 60), 1)
})

test_that("forward visibility falls when the camera sees less of the pitch", {
  wide   <- cbind(c(0, 120, 120, 0), c(0, 0, 80, 80))
  narrow <- cbind(c(0, 120, 120, 0), c(30, 30, 50, 50))
  expect_lt(forward_visibility(narrow, 60), forward_visibility(wide, 60))
})

test_that("forward visibility is undefined right on the goal line", {
  whole <- cbind(c(0, 120, 120, 0), c(0, 0, 80, 80))
  expect_true(is.na(forward_visibility(whole, 120)))
})

test_that("a keeper standing on the line in front of the shooter closes part of the goal", {
  open <- open_goal_share(108, 40, 119, 40, reach = 1)
  expect_gt(open, 0)
  expect_lt(open, 1)
})

test_that("a keeper who comes out closes more of the goal for the shooter", {
  on_line  <- open_goal_share(108, 40, 119.5, 40, reach = 1)
  come_out <- open_goal_share(108, 40, 112, 40, reach = 1)
  expect_lt(come_out, on_line)
})

test_that("a keeper out to the shooter leaves a square teammate an emptier goal", {
  shooter  <- open_goal_share(110, 40, 112, 40, reach = 1)
  teammate <- open_goal_share(114, 30, 112, 40, reach = 1)
  expect_gt(teammate, shooter)
})

test_that("a keeper behind the player closes nothing, and a missing keeper gives NA", {
  expect_equal(open_goal_share(110, 40, 105, 40), 1)
  expect_true(is.na(open_goal_share(110, 40, NA, NA)))
})

test_that("only opponents standing in the lane count as blockers", {
  expect_equal(lane_blockers(c(105, 105), c(40, 50), 100, 40, 110, 40), 1)
  expect_equal(lane_blockers(numeric(0), numeric(0), 100, 40, 110, 40), 0)
  # right on top of the receiver is pressure, not a blocked lane
  expect_equal(lane_blockers(110, 40.2, 100, 40, 110, 40), 0)
})

test_that("the offside line is the second-last opponent, never behind the ball or in the own half", {
  expect_equal(offside_line(c(119, 112, 100), 105), 112)
  expect_equal(offside_line(c(119, 100), 108), 108)
  expect_equal(offside_line(c(50, 40), 30), 60)
})
