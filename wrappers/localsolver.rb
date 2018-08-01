# Copyright © Mapotempo, 2018
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
require './wrappers/wrapper'
require './wrappers/localsolver_vrp_pb'
require './wrappers/localsolver_result_pb'
require 'tempfile'
require 'json'

require 'open3'
require 'thread'

module Wrappers
  class Localsolver < Wrapper
    def initialize(cache, hash = {})
      super(cache, hash)
      @exec_localsolver = hash[:exec_localsolver] || 'LD_LIBRARY_PATH=../optimizer-localsolver/dependencies/install/lib/:../localsolver_8_0/include/ ../optimizer-localsolver/tsp_localsolver'
      @optimize_time = hash[:optimize_time]
      @previous_result = nil

      @semaphore = Mutex.new
    end

    def solver_constraints
      super + [

      ]
    end

    def solve(vrp, job, thread_proc = nil, &block)
      problem_units = vrp.units.collect{ |unit|
        {
          unit_id: unit.id,
          fill: false,
          empty: false
        }
      }
      vrp.services.each{ |service|
        service.quantities.each{ |quantity|
          unit_status = problem_units.find{ |unit| unit[:unit_id] == quantity.unit_id }
          unit_status[:fill] ||= quantity.fill
          unit_status[:empty] ||= quantity.empty
        }
      }
      @job = job
      @previous_result = nil
      points = Hash[vrp.points.collect{ |point| [point.id, point] }]
      services = vrp.services.collect{ |service|
        LocalsolverVrp::Service.new(
          time_windows: service.activity.timewindows.collect{ |tw| LocalsolverVrp::TimeWindow.new(
            start: tw.start || 0,
            end: tw.end || 0,
          )},
          quantities: vrp.units.collect{ |unit|
            is_empty_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:empty]
            q = service.quantities.find{ |quantity| quantity.unit == unit }
            q && q.value ? (is_empty_unit ? -1 : 1) * (service.type.to_s == "delivery" ? -1 : 1) * (q.value*(unit.counting ? 1 : 1)+0.5).to_i : 0
          },
          matrix_index: points[service.activity.point_id].matrix_index,
          id: service.id,
          duration: service.activity.duration
        )
      }
      matrix_indices = vrp.services.collect{ |service|
        points[service.activity.point_id].matrix_index
      }
      matrices = vrp.matrices.collect{ |matrix|
        LocalsolverVrp::Matrix.new(
          time: matrix[:time] ? matrix[:time].flatten : [],
          distance: matrix[:distance] ? matrix[:distance].flatten : [],
          value: matrix[:value] ? matrix[:value].flatten : []
        )
      }
      vehicles = vrp.vehicles.sort!{ |a, b|
        a.global_day_index && b.global_day_index && a.global_day_index != b.global_day_index ? a.global_day_index <=> b.global_day_index : a.id <=> b.id
      }.collect{ |vehicle|
        LocalsolverVrp::Vehicle.new(
          id: vehicle.id,
          capacities: vrp.units.collect{ |unit|
            q = vehicle.capacities.find{ |capacity| capacity.unit == unit }
            LocalsolverVrp::Capacity.new(
              limit: q && q.limit ? unit.counting ? q.limit : (q.limit*1000+0.5).to_i : -2147483648,
              overload_multiplier: (q && q.overload_multiplier) || 0,
              counting: (unit && unit.counting) || false
            )
          },
          time_window: LocalsolverVrp::TimeWindow.new(
            start: (vehicle.timewindow && vehicle.timewindow.start) || 0,
            end: (vehicle.timewindow && vehicle.timewindow.end) || 2147483647,
          ),
          matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.matrix_id },
          value_matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.value_matrix_id } || 0,
          start_index: vehicle.start_point ? points[vehicle.start_point_id].matrix_index : -1,
          end_index: vehicle.end_point ? points[vehicle.end_point_id].matrix_index : -1,
          day_index: vehicle.global_day_index ? vehicle.global_day_index : -1
        )
      }
      routes = vrp.routes.collect{ |route|
        if !route.vehicle.nil? && !route.mission_ids.empty?
          LocalsolverVrp::Route.new(
            vehicle_id: route.vehicle.id,
            service_ids: route.mission_ids
          )
        end
      }

      problem = LocalsolverVrp::Problem.new(
        vehicles: vehicles,
        services: services,
        matrices: matrices,
        routes: routes
      )

      ret = run_localsolver(problem, vrp, services, points, matrix_indices, thread_proc, &block)
      case ret
      when String
        return ret
      when Array
        cost, result = ret
      else
        return ret
      end
      result
    end

    def kill
      @killed = true
    end

    def build_quantities(job, job_loads)
      if job_loads
        job_loads.collect{ |current_load|
          associated_quantity = job.quantities.find{ |quantity| quantity.unit && quantity.unit.id == current_load[:unit].id} if job
          {
            unit: current_load[:unit],
            value: associated_quantity && associated_quantity.value,
            setup_value: current_load[:unit].counting ? associated_quantity && associated_quantity.setup_value : nil,
            current_load: current_load[:current_load]
          }.delete_if{ |k, v| !v }.compact
        }
      else
        job.quantities.collect{ |quantity|
          if quantity.unit
            {
              unit: quantity.unit,
              value: quantity.value,
              setup_value: quantity.unit.counting ? quantity.setup_value : 0
            }
          end
        }.compact
      end
    end

    def build_rest(rest, day_index)
      {
        duration: rest.duration,
        timewindows: build_timewindows(rest, day_index)
      }
    end

    def build_detail(job, activity, point, day_index, job_load, vehicle)
      {
        lat: point && point.location && point.location.lat,
        lon: point && point.location && point.location.lon,
        skills: job && job.skills,
        timewindows: activity && build_timewindows(activity, day_index),
        quantities: build_quantities(job, job_load),
        router_mode: vehicle ? vehicle.router_mode : nil,
        speed_multiplier: vehicle ? vehicle.speed_multiplier : nil
      }.delete_if{ |k, v| !v }.compact
    end

    def parse_output(vrp, services, points, matrix_indices, cost, output)
      if vrp.vehicles.size == 0 || (vrp.services.nil? || vrp.services.size == 0) && (vrp.shipments.nil? || vrp.shipments.size == 0)
        empty_result = {
          solvers: ['localsolver'],
          cost: 0,
          routes: [],
        }
        return empty_result
      end
      content = LocalsolverResult::Result.decode(output.read)
      output.rewind
      return @previous_result if content['routes'].empty? && @previous_result
      collected_indices = []
      collected_rests_indices = []
      {
        cost: content['cost'].to_i || 0,
        solvers: ['localsolver'],
        routes: content['routes'].each_with_index.collect{ |route, index|
          vehicle = vrp.vehicles[index]
          previous = nil
          load_status = vrp.units.collect{ |unit|
            {
              unit: unit,
              current_load: 0
            }
          }
          route_start = vehicle.timewindow && vehicle.timewindow[:start] ? vehicle.timewindow[:start] : 0
          earliest_start = route_start
          {
          vehicle_id: vehicle.id,
          activities: route['activities'].collect{ |activity|
            current_index = activity['index'] || 0
            activity_loads = load_status.collect.with_index{ |load_quantity, index|
              {
                unit: vrp.units.find{ |unit| unit.id == load_quantity[:unit].id },
                current_load: (activity['quantities'][index] || 0).round(2)
              }
            }
            if activity['type'] == 'start' && activity['index'] == -1
              load_status = build_quantities(nil, activity_loads)
              if  vehicle.start_point
                previous_index = points[vehicle.start_point.id].matrix_index
                {
                  point_id: vehicle.start_point.id,
                  detail: build_detail(nil, nil, vehicle.start_point, nil, activity_loads, vehicle)
                }.delete_if{ |k, v| !v }
              end
            elsif activity['type'] == 'end' && activity['index'] == -1
              {
                point_id: vehicle.end_point.id,
                detail: vehicle.end_point.location ? {
                  lat: vehicle.end_point.location.lat,
                  lon: vehicle.end_point.location.lon,
                #   quantities: activity_loads.collect{ |current_load|
                #     {
                #       unit: current_load[:unit],
                #       value: current_load[:current_load]
                #     }
                #   }
                } : nil
              }.delete_if{ |k, v| !v }
            else
              collected_indices << current_index
              point_index = vrp.points[current_index].matrix_index
              point = vrp.points[current_index]
              service = vrp.services[current_index]
              earliest_start = activity['start_time'] || 0
              travel_time = (previous_index && point_index && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time][previous_index][point_index] : 0)
              travel_distance = (previous_index && point_index && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance][previous_index][point_index] : 0)
              current_activity = {
                service_id: vrp.services[activity['index']].id,
                point_id: point ? point.id : nil,
                travel_time: travel_time,
                travel_distance: travel_distance,
                begin_time: earliest_start,
                departure_time: earliest_start + vrp.services[current_index-1].activity.duration.to_i,
                detail: build_detail(service, activity['index'], point, vehicle.global_day_index ? vehicle.global_day_index%7 : nil, activity_loads, vehicle)
              }.delete_if{ |k, v| !v }
              previous_index = point_index
              current_activity
            end
          }
          }
        }
      }
    end

    def run_localsolver(problem, vrp, services, points, matrix_indices, thread_proc = nil, &block)
      logger = Logger.new(STDERR)
      if vrp.vehicles.size == 0 || (vrp.services.nil? || vrp.services.size == 0) && (vrp.shipments.nil? || vrp.shipments.size == 0)
        return [0, 0, @previous_result = parse_output(vrp, services, points, matrix_indices, 0, nil, nil)]
      end
      encoded_vrp = LocalsolverVrp::Problem.encode(problem)
      input = Tempfile.new('optimize-localsolver-input', tmpdir=@tmp_dir)
      input.write(encoded_vrp)
      input.close

      output = Tempfile.new('optimize-localsolver-output', tmpdir=@tmp_dir)

      cmd = [
        "#{@exec_localsolver} ",
        "-instance_file '#{input.path}'",
        "-solution_file '#{output.path}'"].compact.join(' ')
      puts cmd
      stdin, stdout_and_stderr, @thread = @semaphore.synchronize {
        Open3.popen2e(cmd) if !@killed
      }

      return if !@thread

      pipe = @semaphore.synchronize {
        IO.popen("ps -ef | grep #{@thread.pid}")
      }

      childs = pipe.readlines.map do |line|
        parts = line.split(/\s+/)
        parts[1].to_i if parts[2] == @thread.pid.to_s
      end.compact || []
      childs << @thread.pid

      if thread_proc
        thread_proc.call(childs)
      end
      out = ''
      cost = nil
      time = 0.0
      
      # read of stdout_and_stderr stops at the end of process
      stdout_and_stderr.each_line { |line|
        puts (@job ? @job + ' - ' : '') + line
        out = out + line
        s = /Objective value : ([0-9.eE+]+)/.match(line)
        s && (cost = Integer(s[1].to_i))
        t = 0
        @previous_result = parse_output(vrp, services, points, matrix_indices, cost, output) if s
        if block && s
          block.call(self, nil, nil, cost, t, @previous_result)
        end
      }

      result = out.split("\n")[-1]
      if @thread.value == 0
        if result == 'No solution found...'
          nil
        else
          cost = if result.to_s.include?('Objective value : ')
            result.split(' ')[-1].to_i
          end
          @previous_result = parse_output(vrp, services, points, matrix_indices, cost, output)
          if block
            block.call(self, nil, nil, cost, time, @previous_result)
          end
          [cost, @previous_result = parse_output(vrp, services, points, matrix_indices, cost, output)]
        end
      elsif @thread.value == 9
        out = "Job killed"
        puts out
        out
      end
    ensure
      input && input.unlink
      output && output.unlink
    end

  end
end
