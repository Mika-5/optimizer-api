# Copyright © Mapotempo, 2016
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
require './test/test_helper'
require './test/factory/factory_model_test.rb'

class Wrappers::OrtoolsTest < Minitest::Test

  def test_minimal_problem
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 1, service: 2)

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_group_overall_duration_first_vehicle
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:vehicles] = [attributes_for(:vehicle, cost_fixed: 20),
                          attributes_for(:vehicle),
                          attributes_for(:vehicle)]
    problem[:relations] = [{
                            type: 'vehicle_group_duration',
                            linked_vehicle_ids: ['vehicle_0','vehicle_2'],
                            lapse: 2
                          }]

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_periodic_overall_duration
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:vehicles] = [attributes_for(:vehicle, overall_duration: 3, timewindow: {start: 0}),
                          attributes_for(:vehicle, timewindow: {start: 0})]
    problem[:services] = attributes_for_list(:service, 2, duration: 1)
    problem[:configuration] = attributes_for(:configuration, duration: 1000, range_indices: {start: 0, end: 2})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal result[:routes][0][:activities].size, result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_periodic_with_group_duration
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:services] = attributes_for_list(:service, 2, duration: 1)
    problem[:vehicles] = attributes_for_list(:vehicle, 3, timewindow: {start: 0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration',
                            linked_vehicle_ids: ['vehicle_0','vehicle_1'],
                            lapse: 1
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 1000, range_indices: {start: 0, end: 2})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 3, result[:routes][2][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_with_rest
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:rests] = [attributes_for(:rest, timewindows: [{start: 1, end: 1}])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_fixed: 20, timewindow: {start: 0}),
                          attributes_for(:vehicle, rest_ids: ['rest_0'], overall_duration: 1, sequence_timewindows: [{start: 0, end: 5}])]
    problem[:configuration] = attributes_for(:configuration, duration: 1000, range_indices: {start: 0, end: 1})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_with_rest_no_vehicle_tw
    # conflict with rests
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:rests] = [attributes_for(:rest, timewindows: [{day_index: 0}])]
    problem[:vehicles] = [attributes_for(:vehicle, timewindow: {start: 1, end: 10}, overall_duration: 1),
                          attributes_for(:vehicle, timewindow: {start: 1, end: 10}, rest_ids: ['rest_0'], overall_duration: 1)]
    problem[:configuration] = attributes_for(:configuration, duration: 1000, range_indices: {start: 0, end: 1})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:routes].find{ |route| route[:vehicle_id] == 'vehicle_1_0' }[:activities].size
    assert_equal 2, result[:routes].find{ |route| route[:vehicle_id] == 'vehicle_0_0' }[:activities].size
    assert_equal 0, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_duration_adjusted_by_presence_of_rest
    # conflict with rest
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:rests] = [attributes_for(:rest, timewindows: [{start: 0, end: 1}])]
    problem[:vehicles] = [attributes_for(:vehicle, rest_ids: ['rest_0'], duration: 1, start_point_id: nil, end_point_id: "point_0")]

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert_equal 1, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_with_rest
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:rests] = [attributes_for(:rest, timewindows: [{start: 1, end: 1}])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_fixed: 20, timewindow: {start: 0}),
                          attributes_for(:vehicle, rest_ids: ['rest_0'], overall_duration: 1, sequence_timewindows: [{start: 0, end: 5}])]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_indices: {start: 0, end: 1})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_on_weeks
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2, 2],[2, 0, 2],[2, 2, 0]])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start: 0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration_on_weeks',
                            linked_vehicle_ids: ['vehicle_0','vehicle_1'],
                            lapse: 5,
                            periodicity: 1
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_indices: {start: 5, end: 7})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_on_weeks_date
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2, 2],[2, 0, 2],[2, 2, 0]])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start: 0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration_on_weeks',
                            linked_vehicle_ids: ['vehicle_0','vehicle_1'],
                            lapse: 5,
                            periodicity: 1
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_date: {start: Date.new(2018,3,30), end: Date.new(2018,4,2)})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_on_two_weeks
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2, 2],[2, 0, 2],[2, 2, 0]])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start: 0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration_on_weeks',
                            linked_vehicle_ids: ['vehicle_0','vehicle_1'],
                            lapse: 5,
                            periodicity: 2
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_indices: {start: 5, end: 7})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 1, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_on_two_weeks_date
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2, 2],[2, 0, 2],[2, 2, 0]])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start:  0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration_on_weeks',
                            linked_vehicle_ids: ['vehicle_0','vehicle_1'],
                            lapse: 5,
                            periodicity: 1
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_date: {start: Date.new(2018,3,30), end: Date.new(2018,4,9)})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_on_months
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2, 2],[2, 0, 2],[2, 2, 0]])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start: 0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration_on_months',
                            linked_vehicle_ids: ['vehicle_0','vehicle_1'],
                            lapse: 5,
                            periodicity: 1
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_date: {start: Date.new(2018,3,30), end: Date.new(2018,4,1)})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_overall_duration_on_two_months
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2, 2],[2, 0, 2],[2, 2, 0]])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start: 0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration_on_months',
                            linked_vehicle_ids: ['vehicle_0','vehicle_1'],
                            lapse: 5,
                            periodicity: 2
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_date: {start: Date.new(2018,3,30), end: Date.new(2018,4,1)})

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 1, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_do_not_solve_if_range_index_and_month_duration
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2, 2],[2, 0, 2],[2, 2, 0]])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start: 0})
    problem[:relations] = [{
                            type: 'vehicle_group_duration_on_months',
                            linked_vehicle_ids: ['vehicle_1','vehicle_2'],
                            lapse: 5,
                            periodicity: 1
                          }]
    problem[:configuration] = attributes_for(:configuration, duration: 10, range_indices: {start: 0, end: 2})

    vrp = Models::Vrp.create(problem)
    assert !ortools.inapplicable_solve?(vrp).empty?
    FactoryBot.rewind_sequences
  end

  def test_alternative_stop_conditions
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 1, service: 2)
    problem[:configuration] = attributes_for(:configuration, iterations_without_improvment: 10, initial_time_out: 500, time_out_multiplier: 3, intermediate_solutions: false)

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_loop_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 0, service: 4)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 655, 1948, 5231, 2971],
                                                           [603, 0, 1692, 4977, 2715],
                                                           [1861, 1636, 0, 6143, 1532],
                                                           [5184, 4951, 6221, 0, 7244],
                                                           [2982, 2758, 1652, 7264, 0],
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0")]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_without_start_end_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 0, service: 4)
    problem[:matrices] = [attributes_for(:matrice, time:[
                                                          [0, 655, 1948, 5231, 2971],
                                                          [603, 0, 1692, 4977, 2715],
                                                          [1861, 1636, 0, 6143, 1532],
                                                          [5184, 4951, 6221, 0, 7244],
                                                          [2982, 2758, 1652, 7264, 0],
                                                         ])]
    problem[:vehicles] = [attributes_for(:vehicle, start_point_id: nil)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_with_rest
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:rests] = [attributes_for(:rest, timewindows: [{start: 1, end: 2}])]
    problem[:vehicles] = [attributes_for(:vehicle, rest_ids: ['rest_0'])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + problem[:rests].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_with_rest_multiple_reference
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:rests] = [attributes_for(:rest, timewindows: [{start: 1, end: 2}])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, rest_ids: ['rest_0'])

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size + problem[:vehicles].collect{ |vehicle| vehicle[:rest_ids].size }.inject(:+) + 2, result[:routes].collect{ |route| route[:activities].size }.inject(:+)
    FactoryBot.rewind_sequences
  end

  def test_negative_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 1, service: 0)
    problem[:services] = [attributes_for(:service, timewindows: [{start: -3 , end: 2}]),
                          attributes_for(:service, timewindows: [{start: 5 , end: 7}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_quantities
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 1, vehicle: 0, service: 0)
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, limit: 10)]
    problem[:services] = attributes_for_list(:service_with_capacity, 2, value: 8)

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1 - 1, result[:routes][0][:activities].size
    assert_equal 1, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_vehicles_timewindow_soft
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 1, vehicle: 0, service: 2)
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0", cost_late_multiplier: 1, timewindow: {start: 10, end: 12})]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal 0, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_vehicles_timewindow_hard
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 1, vehicle: 0, service: 2)
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0", cost_late_multiplier: 0, timewindow: {start:10, end: 12})]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][0][:activities].size
    assert_equal 1, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_multiples_vehicles
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 1, vehicle: 0, service: 2)
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", cost_late_multiplier: 0, timewindow: {start:10, end: 12})

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][0][:activities].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][1][:activities].size
    assert_equal 0, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_double_soft_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 1, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 5, 5],[5, 0, 5],[5, 5, 0]])]
    problem[:services] = [attributes_for(:service, late_multiplier: 1, timewindows: [{start: 3, end: 4}, {start: 7, end: 8}]),
                          attributes_for(:service, late_multiplier: 1, timewindows: [{start: 5, end: 6}, {start: 10, end: 11}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_triple_soft_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 1, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 5, 5],[5, 0, 5],[5, 5, 0]])]
    problem[:services] = [attributes_for(:service, timewindows: [{start: 3, end: 4}, {start: 7, end: 8}, {start: 11, end: 12}]),
                          attributes_for(:service, timewindows: [{start: 5, end: 6}, {start: 10, end: 11}, {start: 15, end: 16}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_double_hard_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 1, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 5, 5],[5, 0, 5],[5, 5, 0]])]
    problem[:services] = [attributes_for(:service, timewindows: [{start: 3, end: 4}, {start: 7, end: 8}]),
                          attributes_for(:service, timewindows: [{start: 5, end: 6}, {start: 10, end: 11}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size , result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_triple_hard_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 1, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 9, 9],[9, 0, 9],[9, 9, 0]])]
    problem[:services] = [attributes_for(:service, timewindows: [{start: 3, end: 4}, {start: 7, end: 8}, {start: 11, end: 12}]),
                          attributes_for(:service, timewindows: [{start: 5, end: 6}, {start: 10, end: 11}, {start: 15, end: 16}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size , result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_timewindows_intersection
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 1, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2],[2, 0]])]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0")]
    problem[:services] = [attributes_for(:service, timewindows: [{start: 0, end: 5}, {start: 5, end: 10}, {start: 8, end: 16}])]

    vrp = Models::Vrp.create(problem)
    assert !ortools.assert_services_no_timewindows_overlap(vrp)
    result = ortools.solve(vrp, 'test')
    FactoryBot.rewind_sequences
  end

  def test_no_timewindows_intersection
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 2, unit: 1, vehicle: 1, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [[0, 2],[2, 0]])]
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, end_point_id: "point_0", limit: 10)]
    problem[:services] = [attributes_for(:service_with_capacity, late_multiplier: 1, timewindows: [{start: 3, end: 4}], value: 8)]

    vrp = Models::Vrp.create(problem)
    assert ortools.assert_services_no_timewindows_overlap(vrp)
    result = ortools.solve(vrp, 'test')
    FactoryBot.rewind_sequences
  end

  def test_nearby_specific_ordder
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 9, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 6, 10, 127, 44, 36, 42, 219, 219],
                                                           [64, 0, 4, 122, 38, 31, 36, 214, 214],
                                                           [60, 44, 0, 117, 34, 27, 32, 209, 209],
                                                           [68, 53, 8, 0, 42, 35, 40, 218, 218],
                                                           [53, 38, 42, 111, 0, 20, 25, 203, 203],
                                                           [61, 18, 22, 118, 7, 0, 5, 210, 210],
                                                           [77, 12, 17, 134, 50, 43, 0, 226, 226],
                                                           [180, 184, 188, 244, 173, 166, 171, 0, 0],
                                                           [180, 184, 188, 244, 173, 166, 171, 0, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, start_point_id: "point_7", end_point_id: "point_8")]
    problem[:services] = (0..6).collect{ |i|
                            attributes_for(:service, id: "service_#{i}", activity: attributes_for(:activity, point_id: "point_#{i}"))
                          }
    problem[:configuration] = attributes_for(:configuration, duration: 100, intermediate_solutions: false, prefer_short_segment: true)

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert result[:routes][0][:activities][1..-2].collect.with_index{ |activity, index| activity[:service_id] == "service_#{index}" }.all?
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_distance_matrix
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 3)
    problem[:matrices] = [attributes_for(:matrice, time: nil, distance: [
                                                                          [0, 3, 3, 3],
                                                                          [3, 0, 3, 3],
                                                                          [3, 3, 0, 3],
                                                                          [3, 3, 3, 0]
                                                                         ])]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0")]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_max_ride_distance
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 3)
    problem[:matrices] = [attributes_for(:matrice, time: nil, distance: [
                                                                          [0, 1000, 3, 3],
                                                                          [1000, 0, 1000, 1000],
                                                                          [3, 1000, 0, 3],
                                                                          [3, 1000, 3, 0]
                                                                         ])]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0", cost_time_multiplier: 0, cost_distance_multiplier: 1, maximum_ride_distance: 4)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_two_vehicles_one_matrix_each
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 1, 1, 1000],
                                                           [1, 0, 1, 1000],
                                                           [1, 1, 0, 1000],
                                                           [1000, 1000, 1000, 0]
                                                          ]),
                          attributes_for(:matrice, id: "matrix_1", time: [
                                                                          [0, 1, 1, 1000],
                                                                          [1, 0, 1, 1000],
                                                                          [1, 1, 0, 1000],
                                                                          [1000, 1000, 1000, 0]
                                                                         ])]
    problem[:vehicles] = (0..1).collect{ |i|
                             attributes_for(:vehicle, end_point_id: "point_0", matrix_id: "matrix_#{i}")
                         }
    problem[:services] = attributes_for_list(:service, 3, timewindows: [{start: 2980, end: 3020}])

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 4, result[:routes][0][:activities].size
    assert_equal 3, result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_skills
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 3],
                                                           [3, 0, 3, 3],
                                                           [3, 3, 0, 3],
                                                           [3, 3, 3, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0", cost_time_multiplier: 1, skills: [['frozen']]),
                          attributes_for(:vehicle, end_point_id: "point_0", skills: [['cool']])]
    problem[:services] = [attributes_for(:service, skills: ["frozen"]),
                          attributes_for(:service, skills: ["cool"]),
                          attributes_for(:service, skills: ["frozen"]),
                          attributes_for(:service, skills: ["cool"], activity: {point_id: "point_3"})]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 4, result[:routes][0][:activities].size
    assert_equal 4, result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_setup_duration
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 5, 5],
                                                           [5, 0, 5],
                                                           [5, 5, 0]
                                                          ])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", timewindow: {start: 3, end: 16})
    problem[:services] = attributes_for_list(:service, 2, setup_duration: 2, duration: 1, timewindows: [{start: 3, end: 4}, {start: 7, end: 8}])

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size , result[:routes][0][:activities].size - 1
    assert_equal problem[:services].size , result[:routes][1][:activities].size - 1
    FactoryBot.rewind_sequences
  end

  def test_pickup_delivery
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 3],
                                                           [3, 0, 3, 3],
                                                           [3, 3, 0, 3],
                                                           [3, 3, 3, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, cost_time_multiplier: 1, end_point_id: "point_0", limit: 10)]
    problem[:services] = [attributes_for(:service_with_capacity, type: "pickup", value: 4),
                          attributes_for(:service_with_capacity, type: "pickup", value: 4),
                          attributes_for(:service_with_capacity, type: "delivery", value: 10),
                          attributes_for(:service_with_capacity, type: "delivery", activity: {point_id: "point_3"}, value: 9)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_pickup_delivery_2
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                          [0, 3, 3, 3],
                                                          [3, 0, 3, 3],
                                                          [3, 3, 0, 3],
                                                          [3, 3, 3, 0]
                                                         ])]
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, cost_time_multiplier: 1, end_point_id: "point_0", limit: 10)]
    problem[:services] = [attributes_for(:service_with_capacity, type: "pickup", activity:{point_id:"point_1"}, value: 9),
                          attributes_for(:service_with_capacity, type: "pickup", activity:{point_id:"point_2"}, value: 9),
                          attributes_for(:service_with_capacity, type: "delivery", activity:{point_id:"point_3"}, value: 9),
                          attributes_for(:service_with_capacity, type: "delivery", activity:{point_id:"point_3"}, value: 9),
                          attributes_for(:service_with_capacity, type: "delivery", activity:{point_id:"point_3"}, value: 9),
                          attributes_for(:service_with_capacity, type: "pickup", activity:{point_id:"point_2"}, value: 9)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 8, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_pickup_delivery_3
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 3, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 3],
                                                           [3, 0, 3, 3],
                                                           [3, 3, 0, 3],
                                                           [3, 3, 3, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle_with_capacities, cost_time_multiplier: 1, end_point_id: "point_0", limit1: 2, limit2: 2)]
    problem[:services] = [attributes_for(:service_with_capacities, type: "service", value1: -1, value2: 1),
                          attributes_for(:service_with_capacities, type: "pickup", value1: 2, value2: -2),
                          attributes_for(:service_with_capacities, type: "delivery", value1: -1, value2: -1),
                          attributes_for(:service_with_capacities, type: "delivery", activity: {point_id:"point_3"}, value1: -3, value2: 3)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size

    assert_equal 'service_3', result[:routes][0][:activities][1][:service_id]
    assert_equal 'service_1', result[:routes][0][:activities][2][:service_id]
    assert_equal 'service_2', result[:routes][0][:activities][3][:service_id]
    FactoryBot.rewind_sequences
  end

  def test_route_duration
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 3],
                                                           [3, 0, 3, 3],
                                                           [3, 3, 0, 3],
                                                           [3, 3, 3, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: "point_0", duration: 9)]
    problem[:services] = [attributes_for(:service, duration: 3),
                          attributes_for(:service, duration: 5),
                          attributes_for(:service, duration: 3)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:unassigned].size
    assert_equal 3, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_route_force_start
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                          [0, 3, 3, 9],
                                                          [3, 0, 3, 8],
                                                          [3, 3, 0, 8],
                                                          [9, 9, 9, 0]
                                                        ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: "point_0", force_start: true)]
    problem[:services] = [attributes_for(:service, timewindows: [{start: 9}]),
                          attributes_for(:service, timewindows: [{start: 18}]),
                          attributes_for(:service, timewindows: [{start: 18}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal "service_1", result[:routes][0][:activities][1][:service_id]
    FactoryBot.rewind_sequences
  end

  def test_route_shift_preference_to_force_start
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 9],
                                                           [3, 0, 3, 8],
                                                           [3, 3, 0, 8],
                                                           [9, 9, 9, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: "point_0", shift_preference: 'force_start')]
    problem[:services] = [attributes_for(:service, timewindows: [{start: 9}]),
                          attributes_for(:service, timewindows: [{start: 18}]),
                          attributes_for(:service, timewindows: [{start: 18}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal "service_1", result[:routes][0][:activities][1][:service_id]
    FactoryBot.rewind_sequences
  end

  def test_route_shift_preference_to_force_end
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 9],
                                                           [3, 0, 3, 8],
                                                           [3, 3, 0, 8],
                                                           [9, 9, 9, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: "point_0", shift_preference: 'force_end')]
    problem[:services] = [attributes_for(:service, timewindows: [{start: 9}]),
                          attributes_for(:service, timewindows: [{start: 18}]),
                          attributes_for(:service, timewindows: [{start: 18}])]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal 18, result[:routes][0][:activities][1][:begin_time]
    FactoryBot.rewind_sequences
  end

  def test_vehicle_limit
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:vehicles] = attributes_for_list(:vehicle, 2, timewindow: {end: 1})
    problem[:configuration] = attributes_for(:configuration, duration: 100, intermediate_solutions: false, vehicle_limit: 1)

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size + result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_minimum_day_lapse
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:vehicles] = (0..4).collect{ |i|
                           attributes_for(:vehicle, start_point_id: nil, global_day_index: i)
                         }
    problem[:services] = [attributes_for(:service),
                          attributes_for(:service),
                          attributes_for(:service, activity: {point_id: "point_2"})]
    problem[:relations] = [{
                            id: 'minimum_lapse_1',
                            type: "minimum_day_lapse",
                            lapse: 2,
                            linked_ids: ['service_1', 'service_2', 'service_3']
                          }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 5, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size + result[:routes][2][:activities].size + result[:routes][4][:activities].size
    assert_equal result[:routes][0][:activities].size, result[:routes][2][:activities].size
    assert_equal result[:routes][2][:activities].size, result[:routes][4][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_maximum_day_lapse
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 1, vehicle: 0, service: 0)
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, global_day_index: 0, limit: 1),
                          attributes_for(:vehicle_with_capacity, global_day_index: 4, limit: 1),
                          attributes_for(:vehicle_with_capacity, global_day_index: 3, limit: 1),
                          attributes_for(:vehicle_with_capacity, global_day_index: 2, limit: 1),
                          attributes_for(:vehicle_with_capacity, global_day_index: 1, limit: 1)]
    problem[:services] = [attributes_for(:service_with_capacity, value: 1),
                          attributes_for(:service_with_capacity, value: 1),
                          attributes_for(:service_with_capacity, activity: {point_id: "point_2"}, value: 1)]
    problem[:relations] = [{
                            id: 'maximum_lapse_1',
                            type: "maximum_day_lapse",
                            lapse: 1,
                            linked_ids: ['service_1', 'service_2']
                          },{
                            id: 'maximum_lapse_2',
                            type: "maximum_day_lapse",
                            lapse: 1,
                            linked_ids: ['service_1', 'service_3']
                          }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 5, result[:routes].size
    assert_equal 1, result[:unassigned].size
    assert problem[:vehicles].find{ |vehicle| result[:routes].find{ |route|
      route[:activities].one?{ |activity| activity[:service_id] == ('service_2' || 'service_3') }
    }[:vehicle_id] == vehicle[:id] }[:global_day_index] - problem[:vehicles].find{ |vehicle| result[:routes].find{ |route|
      route[:activities].one?{ |activity| activity[:service_id]  == 'service_1' }
    }[:vehicle_id] == vehicle[:id] }[:global_day_index] == 1
    FactoryBot.rewind_sequences
  end

  def test_counting_quantities
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 0, vehicle: 0, service: 0)
    problem[:units] = [attributes_for(:unit, counting: true)]
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 1, 1, 1],
                                                           [1, 0, 1, 1],
                                                           [1, 1, 0, 1],
                                                           [1, 1, 1, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, limit: 2)]
    problem[:services] = [attributes_for(:service_with_capacity, activity: {point_id: "point_1"}, setup_value: 1),
                          attributes_for(:service_with_capacity, activity: {point_id: "point_1"}, setup_value: 1),
                          attributes_for(:service_with_capacity, activity: {point_id: "point_2"}, setup_value: 1),
                          attributes_for(:service_with_capacity, activity: {point_id: "point_3"}, setup_value: 1)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1 - 1, result[:routes][0][:activities].size
    assert_equal 1, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_shipments
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 9],
                                                           [3, 0, 3, 8],
                                                           [3, 3, 0, 8],
                                                           [9, 9, 9, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: "point_0", cost_time_multiplier: 1)]
    problem[:shipments] = [attributes_for(:shipment, pointPickup: 'point_3', pointDelivery: 'point_2'),
                           attributes_for(:shipment, pointPickup: 'point_1', pointDelivery: 'point_3')]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_shipments_quantities
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                          [0, 3, 3],
                                                          [3, 0, 3],
                                                          [3, 3, 0]
                                                         ])]
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, cost_time_multiplier: 1, end_point_id: 'point_0', limit: 2)]
    problem[:shipments] = [attributes_for(:shipment_with_capacity, pointPickup: 'point_1', pointDelivery: 'point_2', value: 2),
                           attributes_for(:shipment_with_capacity, pointPickup: 'point_1', pointDelivery: 'point_2', value: 2)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} + 1 == result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} + 1 == result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_shipments_inroute_duration
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                          [0, 3, 3, 9],
                                                          [3, 0, 3, 8],
                                                          [3, 3, 0, 8],
                                                          [9, 9, 9, 0]
                                                         ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0')]
    problem[:shipments] = [attributes_for(:shipment, pointPickup: 'point_3', pointDelivery: 'point_2', max_inroute_duration: 12),
                           attributes_for(:shipment, pointPickup: 'point_1', pointDelivery: 'point_3', max_inroute_duration: 12)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal result[:routes][0][:activities].find_index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } + 1, result[:routes][0][:activities].find_index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    assert_equal result[:routes][0][:activities].find_index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } + 1, result[:routes][0][:activities].find_index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_mixed_shipments_and_services
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 1, 1, 1],
                                                           [1, 0, 1, 1],
                                                           [1, 1, 0, 1],
                                                           [1, 1, 1, 0]
                                                         ])]
    problem[:services] = [attributes_for(:service_with_capacity, setup_value: 1)]
    problem[:shipments] = [attributes_for(:shipment, pointPickup: 'point_2', pointDelivery: 'point_3')]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0')]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_shipments_distance
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: nil, distance: [
                                                                          [0, 3, 3, 9],
                                                                          [3, 0, 3, 8],
                                                                          [3, 3, 0, 8],
                                                                          [9, 9, 9, 0]
                                                                        ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 0, cost_distance_multiplier: 1, end_point_id: 'point_0')]
    problem[:shipments] = [attributes_for(:shipment, pointPickup: 'point_3', pointDelivery: 'point_2'),
                           attributes_for(:shipment, pointPickup: 'point_3', pointDelivery: 'point_1')]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_maximum_duration_lapse_shipments
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 3, 3, 9],
                                                           [3, 0, 3, 8],
                                                           [3, 3, 0, 8],
                                                           [9, 9, 9, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0')]
    problem[:shipments] = [attributes_for(:shipment, pointPickup: 'point_3', timewindowPickup: [{start: 0, end: 100}], pointDelivery: 'point_2', timewindowDelivery: [{start: 300, end: 400}]),
                           attributes_for(:shipment, pointPickup: 'point_1', timewindowPickup: [{start: 0, end: 100}], pointDelivery: 'point_3', timewindowDelivery: [{start: 100, end: 200}])]
    problem[:relations] = [{
                            type: "maximum_duration_lapse",
                            lapse: 100,
                            linked_ids: ["shipment_0pickup", "shipment_0delivery"]
                          },{
                            type: "maximum_duration_lapse",
                            lapse: 100,
                            linked_ids: ["shipment_1pickup", "shipment_1delivery"]
                          }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 4, result[:routes][0][:activities].size
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 2, result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_pickup_timewindow_after_delivery_timewindow
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 1, 1, 1],
                                                           [1, 0, 1, 1],
                                                           [1, 1, 0, 1],
                                                           [1, 1, 1, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0')]
    problem[:shipments] = [attributes_for(:shipment, pointPickup: 'point_1', timewindowPickup: [{start: 6, end: 9}], pointDelivery: 'point_2', timewindowDelivery: [{start: 1, end: 5}])]

    vrp = Models::Vrp.create(problem)
    assert !ortools.assert_no_pickup_timewindows_after_delivery_timewindows(vrp)
    result = ortools.solve(vrp, 'test')
    FactoryBot.rewind_sequences
  end

  def test_value_matrix
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 1, 1, 1],
                                                           [1, 0, 1, 1],
                                                           [1, 1, 0, 1],
                                                           [1, 1, 1, 0]
                                                          ], 
                                                  value: [
                                                           [0, 1, 1, 1],
                                                           [1, 0, 1, 1],
                                                           [1, 1, 0, 1],
                                                           [1, 1, 1, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, cost_value_multiplier: 1),
                          attributes_for(:vehicle, cost_time_multiplier: 10, cost_value_multiplier: 0.5)]
    problem[:services] = [attributes_for(:service, activity: {point_id: "point_1"}),
                          attributes_for(:service, activity: {point_id: "point_1"}),
                          attributes_for(:service, activity: {point_id: "point_2"}),
                          attributes_for(:service, activity: {point_id: "point_3", additional_value:90})]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 4, result[:routes][0][:activities].size
    assert_equal 2, result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_sequence
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 4, unit: 1, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 1, 2, 5],
                                                           [1, 0, 2, 10],
                                                           [1, 2, 0, 5],
                                                           [1, 3, 8, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0'),
                          attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0', skills: [['skill1']])]
    problem[:services] = [attributes_for(:service, skills: ['skill1']),
                          attributes_for(:service),
                          attributes_for(:service)]
    problem[:relations] = [{
                            id: 'sequence_1',
                            type: "sequence",
                            linked_ids: ['service_1', 'service_3', 'service_2']
                          }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 5, result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_unreachable_destination
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 0, unit: 1, vehicle: 0, service: 0)
    problem[:points] = [attributes_for(:pointLocation, lat: 43.8, lon: 5.8),
                        attributes_for(:pointLocation, lat: -43.8, lon: 5.8),
                        attributes_for(:pointLocation, lat: 44.8, lon: 4.8),
                        attributes_for(:pointLocation, lat: 44.0, lon: 5.1)]
    problem[:vehicles] = [{
                          id: "vehicle_1",
                          cost_time_multiplier: 1.0,
                          cost_waiting_time_multiplier: 1.0,
                          cost_distance_multiplier: 1.0,
                          router_mode: "car",
                          router_dimension: "time",
                          speed_multiplier: 1.0,
                          start_point_id: "point_3",
                          end_point_id: "point_3"
                        }]
    problem[:services] = attributes_for_list(:service, 3, duration: 100)

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
    assert result
    assert_equal 4, result[:routes][0][:activities].size
    assert result[:cost] < 2 ** 32
    FactoryBot.rewind_sequences
  end

  def test_initial_load_output
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 2, vehicle: 0, service: 0)
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, limit: 5)]
    problem[:services] = [attributes_for(:service_with_capacities, value1: -5),
                          attributes_for(:service_with_capacities, value1: 4, value2: -1)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal 5, result[:routes].first[:initial_loads].first[:value]
    assert_equal 1, result[:routes].first[:initial_loads][1][:value]
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_force_first
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:vehicles] = attributes_for_list(:vehicle, 3, start_point_id: nil)
    problem[:services] = [attributes_for(:service),
                          attributes_for(:service),
                          attributes_for(:service, activity: {point_id: "point_2"})]
    problem[:relations] = [{
                             id: 'force_first',
                             type: "force_first",
                             linked_ids: ['service_1', 'service_3']
                           }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 3, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size + result[:routes][1][:activities].size
    assert_equal 'service_1', result[:routes][0][:activities].first[:service_id]
    assert_equal 'service_3', result[:routes][1][:activities].first[:service_id]
    FactoryBot.rewind_sequences
  end

  def test_force_end
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:vehicles] = attributes_for_list(:vehicle, 2, start_point_id: nil)
    problem[:services] = [attributes_for(:service),
                          attributes_for(:service),
                          attributes_for(:service, activity: {point_id: "point_2"})]
    problem[:relations] = [{
                            id: 'force_end',
                            type: "force_end",
                            linked_ids: ['service_1']
                          }, {
                            id: 'force_end2',
                            type: "force_end",
                            linked_ids: ['service_3']
                          }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size + result[:routes][1][:activities].size
    assert_equal 'service_1', result[:routes][0][:activities].last[:service_id]
    assert_equal 'service_3', result[:routes][1][:activities].last[:service_id]
    FactoryBot.rewind_sequences
  end

  def test_never_first
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:vehicles] = attributes_for_list(:vehicle, 2, start_point_id: nil)
    problem[:services] = [attributes_for(:service),
                          attributes_for(:service),
                          attributes_for(:service, activity: {point_id: "point_2"})]
    problem[:relations] = [{
                            id: 'never_first',
                            type: "never_first",
                            linked_ids: ['service_1', 'service_3']
                          }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size, [result[:routes][0][:activities].size, result[:routes][1][:activities].size].max
    assert_equal 'service_2', result[:routes][0][:activities].first[:service_id] || result[:routes][1][:activities].first[:service_id]
    FactoryBot.rewind_sequences
  end

  def test_fill_quantities
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 1, vehicle: 0, service: 0)
    problem[:vehicles] = [attributes_for(:vehicle_with_capacity, start_point_id: nil, limit:5)]
    problem[:services] = [attributes_for(:service_with_capacity, fill: true),
                          attributes_for(:service_with_capacity, value: -5),
                          attributes_for(:service_with_capacity, activity: {point_id: "point_2"}, value: -5)]
    problem[:relations] = [{
                            id: 'never_first',
                            type: "never_first",
                            linked_ids: ['service_1', 'service_3']
                          }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal problem[:services].size, result[:routes][0][:activities].size
    assert 'service_2' == result[:routes][0][:activities].first[:service_id] || 'service_2' == result[:routes][0][:activities].last[:service_id]
    assert 'service_3' == result[:routes][0][:activities].first[:service_id] || 'service_3' == result[:routes][0][:activities].last[:service_id]
    assert_equal 'service_1', result[:routes][0][:activities][1][:service_id]
    assert_equal result[:routes][0][:initial_loads].first[:value], 5
    FactoryBot.rewind_sequences
  end

  def test_max_ride_time
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                          [0, 5, 11],
                                                          [5, 0, 11],
                                                          [11, 11, 0]
                                                         ])]
    problem[:vehicles] = [attributes_for(:vehicle, maximum_ride_time: 10)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size
    assert_equal 1 , result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_vehicle_max_distance
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 1, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, distance: [
                                                               [0, 11, 9],
                                                               [11, 0, 6],
                                                               [9, 6, 0]
                                                              ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_distance_multiplier: 1, distance: 10),
                          attributes_for(:vehicle, cost_distance_multiplier: 1)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal problem[:services].size + 1 , result[:routes][1][:activities].size
    assert_equal 0 , result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_vehicle_max_distance_one_per_vehicle
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, distance: [
                                                               [0, 5, 11],
                                                               [5, 0, 11],
                                                               [11, 11, 0]
                                                              ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_distance_multiplier: 1, distance: 11),
                          attributes_for(:vehicle, cost_distance_multiplier: 1, distance: 10)]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert_equal result[:routes][0][:activities].size , result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_max_ride_time_never_from_or_to_depot
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 5, 11],
                                                           [5, 0, 11],
                                                           [11, 11, 0]
                                                          ])]
    problem[:vehicles] = attributes_for_list(:vehicle, 2, end_point_id: "point_0", cost_fixed: 10, maximum_ride_time: 10)
    problem[:configuration] = attributes_for(:configuration, duration: 100, intermediate_solutions: false)

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 52, result[:cost]
    assert_equal 3, result[:routes][0][:activities].size
    assert_equal 3, result[:routes][1][:activities].size
    assert_equal 0 , result[:unassigned].size
    FactoryBot.rewind_sequences
  end

  def test_initial_routes
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 4, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
                                                           [0, 1, 1, 1],
                                                           [1, 0, 1, 1],
                                                           [1, 1, 0, 1],
                                                           [1, 1, 1, 0]
                                                          ])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0'),
                          attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0', skills: [['skill1']])]
    problem[:services] = [attributes_for(:service, skills: ['skill1']),
                          attributes_for(:service),
                          attributes_for(:service)]
    problem[:routes] = [{
                          vehicle_id: 'vehicle_0',
                          mission_ids: ['service_1', 'service_3', 'service_2']
                       }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    # Initial routes are soft assignment
    assert_equal 2, result[:routes].size
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 5, result[:routes][1][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_alternative_service
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [attributes_for(:matrice, time: [
[0, 1, 1000],
[1, 0, 1000],
[1000, 1000, 0],
])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_time_multiplier: 1, end_point_id: 'point_0')]
    problem[:services] = [attributes_for(:service, activity: nil, skills: ['skill1'], activities: [{point_id: "point_1"}, {point_id: "point_2"}])]
    problem[:routes] = [{
                          vehicle_id: 'vehicle_0',
                          mission_ids: ['service_1', 'service_3', 'service_2']
                       }]

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal [], result[:unassigned]
    assert_equal 0, result[:routes][0][:activities][1][:alternative]
    FactoryBot.rewind_sequences
  end

  def test_evaluate_only
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 1, service: 2)
    problem[:routes] =  [{
                          mission_ids: ['service_1','service_2'],
                          vehicle_id: 'vehicle_0'
                        }]
    problem[:configuration] = {
                                resolution: {
                                  evaluate_only: true,
                                  duration: 10,
                                }
                              }
    
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 3, result[:routes][0][:activities].size
    assert_equal 2, result[:cost]
    assert_equal 1, result[:iterations]
    FactoryBot.rewind_sequences
  end

  def test_evaluate_only_not_every_service_has_route
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 1, service: 2)
    problem[:routes] = [{
                         mission_ids: ['service_1'],
                         vehicle_id: 'vehicle_0'
                       }]
    problem[:configuration] = {
                                resolution: {
                                  evaluate_only: true,
                                  duration: 10,
                                }
                              }

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
    assert_equal 65, result[:cost]
    assert_equal 1, result[:iterations]
    FactoryBot.rewind_sequences
  end

  def test_evaluate_only_not_every_vehicle_has_route
    ortools = OptimizerWrapper::ORTOOLS
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 2, service: 2)
    problem[:routes] = [{
                         mission_ids: ['service_1','service_2'],
                         vehicle_id: 'vehicle_0'
                       }]
    problem[:configuration] = {
                                resolution: {
                                  evaluate_only: true,
                                  duration: 10,
                                }
                              }

    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 0, result[:unassigned].size
    assert_equal 2, result[:cost]
    assert_equal 1, result[:iterations]
    FactoryBot.rewind_sequences
  end

  def test_evaluate_only_with_computed_solution
    problem = attributes_for(:problem, matrice: 0, point: 3, unit: 0, vehicle: 0, service: 0)
    problem[:matrices] = [{
                          id: 'matrix_0',
                          time: [
                            [0, 2, 2],
                            [2, 0, 2],
                            [2, 2, 0]
                          ]
                        }]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: 'point_0', duration: 6)]
    problem[:services] = [attributes_for(:service, duration: 1),
                          attributes_for(:service, activity: {point_id: 'point_1', duration: 1}),
                          attributes_for(:service, activity: {point_id: 'point_1', duration: 2}),
                          attributes_for(:service, activity: {point_id: 'point_2', duration: 2}),
                          attributes_for(:service, activity: {point_id: 'point_2', duration: 2}),
                          attributes_for(:service, activity: {point_id: 'point_1', duration: 1})]

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 2310, result[:cost]

    problem[:configuration][:resolution][:evaluate_only] = true
    problem[:routes] = [{
      mission_ids: ['service_2','service_1'],
      vehicle_id: 'vehicle_0'
    }]

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert_equal 2310, result[:cost]
    assert_equal 1, result[:iterations]
    FactoryBot.rewind_sequences
  end

end
