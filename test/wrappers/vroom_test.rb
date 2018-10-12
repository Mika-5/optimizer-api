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


class Wrappers::VroomTest < Minitest::Test

  def matriceInit
    return [[0, 655, 1948, 5231, 2971],[603, 0, 1692, 4977, 2715],[1861, 1636, 0, 6143, 1532],[5184, 4951, 6221, 0, 7244],[2982, 2758, 1652, 7264, 0]]
  end

  def test_minimal_problem
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 1, service: 2)

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    progress = 0
    result = vroom.solve(vrp) { |avancement, total|
      progress += 1
    }
    assert result
    assert progress > 0
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_loop_problem
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 0, service: 4)
    problem[:matrices] = [attributes_for(:matrice, time: matriceInit)]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: 'point_0')]

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.sort
    FactoryBot.rewind_sequences
  end

  def test_no_end_problem
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 1, service: 4)
    problem[:matrices] = [attributes_for(:matrice, time: matriceInit)]

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-1].collect{ |a| a[:service_id] }.sort
    FactoryBot.rewind_sequences
  end

  def test_start_different_end_problem
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 1, service: 3)
    problem[:matrices] = [attributes_for(:matrice, time: matriceInit)]
    problem[:vehicles] = [attributes_for(:vehicle, end_point_id: 'point_4')]

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.sort
    FactoryBot.rewind_sequences
  end

  def test_vehicle_time_window
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 1, point: 3, unit: 0, vehicle: 0, service: 2)
    problem[:vehicles] = [attributes_for(:vehicle, cost_late_multiplier: 1, timewindow: {start: 1, end: 10})]

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    FactoryBot.rewind_sequences
  end

  def test_with_rest
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 0, service: 4)
    problem[:matrices] = [attributes_for(:matrice, time: matriceInit)]
    problem[:rests] = [attributes_for(:rest, duration: 1000, timewindows: [{start: 9000, end: 10000}])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_late_multiplier: 1, end_point_id: 'point_0', timewindow: {start: 100, end: 20000}, rest_ids: ['rest_0'])]

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.compact.sort
    assert_equal 3, result[:routes][0][:activities].index{ |a| a[:rest_id] }
    FactoryBot.rewind_sequences
  end

  def test_with_rest_at_the_end
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 0, service: 4)
    problem[:matrices] = [attributes_for(:matrice, time: matriceInit)]
    problem[:rests] = [attributes_for(:rest, duration: 1000, timewindows: [{start: 19000, end: 20000}])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_late_multiplier: 1, end_point_id: 'point_0', timewindow: {start: 100, end: 20000}, rest_ids: ['rest_0'])]

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.compact.sort
    assert_equal 5, result[:routes][0][:activities].index{ |a| a[:rest_id] }
    FactoryBot.rewind_sequences
  end

  def test_with_rest_at_the_start
    vroom = OptimizerWrapper::VROOM
    problem = attributes_for(:problem, matrice: 0, point: 5, unit: 0, vehicle: 0, service: 4)
    problem[:matrices] = [attributes_for(:matrice, time: matriceInit)]
    problem[:rests] = [attributes_for(:rest, duration: 1000, timewindows: [{start: 200, end: 500}])]
    problem[:vehicles] = [attributes_for(:vehicle, cost_late_multiplier: 1, end_point_id: 'point_0', timewindow: {start: 100, end: 20000}, rest_ids: ['rest_0'])]

    vrp = Models::Vrp.create(problem)
    assert vroom.inapplicable_solve?(vrp).empty?
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.compact.sort
    assert_equal 1, result[:routes][0][:activities].index{ |a| a[:rest_id] }
    FactoryBot.rewind_sequences
  end
end
