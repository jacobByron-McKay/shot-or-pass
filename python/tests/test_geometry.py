import math

import numpy as np
import pytest

from shotorpass.geometry import (clip_to_halfplane, forward_visibility, goal_angle, goal_distance,
                                 in_shooting_cone, lane_blockers, offside_line, open_goal_share,
                                 polygon_area)

WHOLE = np.array([[0, 0], [120, 0], [120, 80], [0, 80]])


def test_goal_distance_is_measured_to_the_centre_of_the_goal():
    assert goal_distance(120, 40) == 0
    assert goal_distance(108, 40) == 12
    assert goal_distance(120, 30) == 10


def test_the_goalmouth_subtends_a_wider_angle_from_in_front_than_from_the_side():
    assert goal_angle(108, 40) > goal_angle(108, 10)


def test_angle_from_the_penalty_spot_matches_the_geometry():
    # 12 yards out, dead centre, an 8 yard goal: 2 * atan(4 / 12)
    assert goal_angle(108, 40) == pytest.approx(2 * math.atan(4 / 12), abs=1e-9)


def test_the_shooting_cone_contains_defenders_standing_in_front_of_goal():
    assert in_shooting_cone(115, 40, 100, 40)
    assert not in_shooting_cone(115, 5, 100, 40)


def test_a_defender_behind_the_shooter_is_not_in_the_cone():
    assert not in_shooting_cone(90, 40, 100, 40)


def test_polygon_area_handles_a_known_rectangle():
    square = np.array([[0, 0], [10, 0], [10, 5], [0, 5]])
    assert polygon_area(square) == 50
    assert polygon_area(square[:2]) == 0


def test_clipping_a_rectangle_in_half_halves_its_area():
    rect = np.array([[0, 0], [20, 0], [20, 10], [0, 10]])
    assert polygon_area(clip_to_halfplane(rect, 10)) == 100
    assert polygon_area(clip_to_halfplane(rect, 0)) == 200
    assert len(clip_to_halfplane(rect, 25)) == 0


def test_forward_visibility_is_one_when_the_whole_forward_area_is_in_view():
    assert forward_visibility(WHOLE, 60) == 1


def test_forward_visibility_falls_when_the_camera_sees_less_of_the_pitch():
    narrow = np.array([[0, 30], [120, 30], [120, 50], [0, 50]])
    assert forward_visibility(narrow, 60) < forward_visibility(WHOLE, 60)


def test_forward_visibility_is_undefined_right_on_the_goal_line():
    assert np.isnan(forward_visibility(WHOLE, 120))


def test_a_keeper_on_the_line_in_front_of_the_shooter_closes_part_of_the_goal():
    open_share = open_goal_share(108, 40, 119, 40, reach=1)
    assert 0 < open_share < 1


def test_a_keeper_who_comes_out_closes_more_of_the_goal_for_the_shooter():
    on_line = open_goal_share(108, 40, 119.5, 40, reach=1)
    come_out = open_goal_share(108, 40, 112, 40, reach=1)
    assert come_out < on_line


def test_a_keeper_out_to_the_shooter_leaves_a_square_teammate_an_emptier_goal():
    shooter = open_goal_share(110, 40, 112, 40, reach=1)
    teammate = open_goal_share(114, 30, 112, 40, reach=1)
    assert teammate > shooter


def test_a_keeper_behind_the_player_closes_nothing_and_a_missing_keeper_gives_nan():
    assert open_goal_share(110, 40, 105, 40) == 1
    assert np.isnan(open_goal_share(110, 40, np.nan, np.nan))


def test_only_opponents_standing_in_the_lane_count_as_blockers():
    assert lane_blockers([105, 105], [40, 50], 100, 40, 110, 40) == 1
    assert lane_blockers([], [], 100, 40, 110, 40) == 0
    # right on top of the receiver is pressure, not a blocked lane
    assert lane_blockers([110], [40.2], 100, 40, 110, 40) == 0


def test_the_offside_line_is_the_second_last_opponent_never_behind_the_ball_or_in_the_own_half():
    assert offside_line([119, 112, 100], 105) == 112
    assert offside_line([119, 100], 108) == 108
    assert offside_line([50, 40], 30) == 60
