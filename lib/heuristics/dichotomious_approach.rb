# Copyright © Mapotempo, 2019
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

require './lib/interpreters/split_clustering.rb'
require './lib/clusterers/balanced_kmeans.rb'
require './lib/tsp_helper.rb'
require './lib/helper.rb'
require './util/job_manager.rb'
require 'ai4r'

module Interpreters
  class Dichotomious

    def self.dichotomious_candidate?(service_vrp)
      (service_vrp[:level] && service_vrp[:level] > 0) ||
        (service_vrp[:vrp].vehicles.none?{ |vehicle| vehicle.cost_fixed && !vehicle.cost_fixed.zero? } &&
        service_vrp[:vrp].vehicles.size > service_vrp[:vrp].resolution_dicho_division_vec_limit &&
        !service_vrp[:vrp].scheduling? &&
        # TODO: We should introduce a new parameter to avoid this static definition
        service_vrp[:vrp].services.size - service_vrp[:vrp].routes.map{ |r| r[:mission_ids].size }.sum > 400 &&
        service_vrp[:vrp].shipments.empty? &&
        service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle.cost_late_multiplier.nil? || vehicle.cost_late_multiplier == 0 } &&
        service_vrp[:vrp].services.all?{ |service| service.activity.late_multiplier.nil? || service.activity.late_multiplier == 0 } &&
        service_vrp[:vrp].points.all?{ |point| point.location && point.location.lat && point.location.lon } &&
        service_vrp[:vrp].services.any?{ |service| service.activity.timewindows && !service.activity.timewindows.empty? })
    end

    def self.feasible_vrp(result, service_vrp)
      (result.nil? || (result[:unassigned].size != service_vrp[:vrp].services.size || result[:unassigned].any?{ |unassigned| !unassigned[:reason] }))
    end

    def self.dichotomious_heuristic(service_vrp, job = nil, &block)
      if dichotomious_candidate?(service_vrp)
        puts "COMBIEN IL Y A DE SERVICE : #{service_vrp[:vrp].services.size}"
        set_config(service_vrp)
        t1 = Time.now
        # Must be called to be sure matrices are complete in vrp and be able to switch vehicles between sub_vrp
        if service_vrp[:level].zero?
          service_vrp[:vrp].compute_matrix
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exlusion_cost(service_vrp)
        # Do not solve if vrp has too many vehicles or services - init_duration is set in set_config()
        elsif service_vrp[:vrp].resolution_init_duration.nil? || service_vrp[:vrp].only_one_point?
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exlusion_cost(service_vrp)
          result = OptimizerWrapper.solve([service_vrp], job, block)
        else
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exlusion_cost(service_vrp)
        end
        puts "COMBIEN IL Y A DE SERVICE : #{service_vrp[:vrp].services.size}"
        t2 = Time.now
        if (result.nil? || result[:unassigned].size >= 0.7 * service_vrp[:vrp].services.size) && feasible_vrp(result, service_vrp) &&
           service_vrp[:vrp].vehicles.size > service_vrp[:vrp].resolution_dicho_division_vec_limit && service_vrp[:vrp].services.size > 100 &&
           !service_vrp[:vrp].only_one_point?
          sub_service_vrps = []
          empties_or_fills = []
          loop do
            sub_service_vrps = split(service_vrp, job, &block)
            break if sub_service_vrps.size == 2 || service_vrp[:vrp].only_one_point?
          end
          unassigned_services = []
          ramaining_empties_or_fills = []
          empties_or_fills_used = []
          empties_or_fills = (service_vrp[:vrp].services.select{ |service| service.quantities.any?(&:fill) } +
                             service_vrp[:vrp].services.select{ |service| service.quantities.any?(&:empty) }).uniq

          results = sub_service_vrps.map.with_index{ |sub_service_vrp, index|
            sub_service_vrp[:vrp].resolution_split_number = sub_service_vrps[0][:vrp].resolution_split_number + 1 if !index.zero?
            sub_service_vrp[:vrp].resolution_total_split_number = sub_service_vrps[0][:vrp].resolution_total_split_number if !index.zero?
            if sub_service_vrp[:vrp].resolution_duration
              sub_service_vrp[:vrp].resolution_duration *= sub_service_vrp[:vrp].services.size / service_vrp[:vrp].services.size.to_f * 2
            end
            if sub_service_vrp[:vrp].resolution_minimum_duration
              sub_service_vrp[:vrp].resolution_minimum_duration *= sub_service_vrp[:vrp].services.size / service_vrp[:vrp].services.size.to_f * 2
            end
            puts "sub_service_vrp[:vrp].services   ---   #{sub_service_vrp[:vrp].services.size}"
            puts "empties_or_fills   ---   #{empties_or_fills.size}"
            sub_service_vrp[:vrp].services += empties_or_fills
            puts "sub_service_vrp[:vrp].services   ---   #{sub_service_vrp[:vrp].services.size}"
            sub_service_vrp[:vrp].points += empties_or_fills.collect{ |empty_or_fill| service_vrp[:vrp].points.find{ |point| empty_or_fill.activity.point_id == point.id } }
            update_matrix(service_vrp[:vrp], sub_service_vrp[:vrp])

            result, sub_service_vrp = OptimizerWrapper.define_process([sub_service_vrp], job, &block)

            if index.zero? && result && sub_service_vrps.size == 2
              empties_or_fills_used = Interpreters::SplitClustering.remove_used_empties_and_refills(empties_or_fills, result).compact
              ramaining_empties_or_fills = empties_or_fills - empties_or_fills_used
              puts "empties_or_fills_used   ---   #{empties_or_fills_used.size}"
              puts "ramaining_empties_or_fills   ---   #{ramaining_empties_or_fills.size}"
              empties_or_fills -= empties_or_fills_used

              result[:unassigned].delete_if{ |activity| ramaining_empties_or_fills.map{ |service| service.id }.include?(activity[:service_id]) } if result
              transfer_unused_vehicles(result, sub_service_vrps)
            end
            if result.nil?
              unassigned_services += sub_service_vrp[:vrp].services.collect{ |service|
                sub_service_vrp[:vrp].get_unassigned_info(sub_service_vrp[:vrp], service[:id], service, 'no solution found in dicho sub_problem')
              }
            end
            result
          }
          if sub_service_vrps.size == 2
            service_vrp[:vrp].resolution_split_number = sub_service_vrps[1][:vrp].resolution_split_number
            service_vrp[:vrp].resolution_total_split_number = sub_service_vrps[1][:vrp].resolution_total_split_number
          end
          result = Helper.merge_results(results)
          result[:unassigned] += unassigned_services.uniq
          byebug if service_vrp[:vrp][:services].size != result[:routes].flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact.size + result[:unassigned].map{ |u| u[:service_id] }.size + ramaining_empties_or_fills.size
          result[:elapsed] += (t2 - t1) * 1000
          puts "dicho - level(#{service_vrp[:level]}) A unassigned rate #{result[:unassigned].size}/#{service_vrp[:vrp].services.size}: #{(result[:unassigned].size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"

          remove_bad_skills(service_vrp, result)
          Interpreters::SplitClustering.remove_empty_routes(result)

          byebug if service_vrp[:vrp][:services].size != result[:routes].flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact.size + result[:unassigned].map{ |u| u[:service_id] }.size + ramaining_empties_or_fills.size
          puts "dicho - level(#{service_vrp[:level]}) B unassigned rate #{result[:unassigned].size}/#{service_vrp[:vrp].services.size}: #{(result[:unassigned].size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"

          result = end_stage_insert_unassigned(service_vrp, result, job)
          byebug if service_vrp[:vrp][:services].size != result[:routes].flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact.size + result[:unassigned].map{ |u| u[:service_id] }.size + ramaining_empties_or_fills.size
          Interpreters::SplitClustering.remove_empty_routes(result)
          byebug if service_vrp[:vrp][:services].size != result[:routes].flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact.size + result[:unassigned].map{ |u| u[:service_id] }.size + ramaining_empties_or_fills.size
          if service_vrp[:level].zero?
            # Remove vehicles which are half empty
            Interpreters::SplitClustering.remove_empty_routes(result)
            puts "dicho - before remove_poorly_populated_routes: #{result[:routes].size}"
            Interpreters::SplitClustering.remove_poorly_populated_routes(service_vrp[:vrp], result, 0.5)
            puts "dicho - after remove_poorly_populated_routes: #{result[:routes].size}"
          end
          puts "dicho - level(#{service_vrp[:level]}) C unassigned rate #{result[:unassigned].size}/#{service_vrp[:vrp].services.size}: #{(result[:unassigned].size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"
        end
      else
        service_vrp[:vrp].resolution_init_duration = nil
      end
      result
    end

    def self.update_matrix(vrp, sub_vrp)
      matrix_indices = sub_vrp.points.map{ |point|
        vrp.points.find{ |r_point| point.id == r_point.id }.matrix_index
      }
      SplitClustering.update_matrix_index(sub_vrp)
      SplitClustering.update_matrix(vrp.matrices, sub_vrp, matrix_indices)
    end

    def self.transfer_unused_vehicles(result, sub_service_vrps)
      result[:routes].each{ |r|
        if r[:activities].select{ |a| a[:service_id] }.empty?
          vehicle = sub_service_vrps[0][:vrp].vehicles.find{ |v| v.id == r[:vehicle_id] }
          sub_service_vrps[1][:vrp].vehicles << vehicle
          sub_service_vrps[0][:vrp].vehicles -= [vehicle]
          sub_service_vrps[1][:vrp].points += sub_service_vrps[0][:vrp].points.select{ |p| p.id == vehicle.start_point_id || p.id == vehicle.end_point_id }
          sub_service_vrps[1][:vrp].resolution_vehicle_limit += 1
        end
      }
      sub_service_vrps[0][:vrp].vehicles.each{ |vehicle|
        next if !result[:routes].select{ |r| r[:vehicle_id] == vehicle.id }.empty?
        sub_service_vrps[1][:vrp].vehicles << vehicle
        sub_service_vrps[0][:vrp].vehicles -= [vehicle]
        sub_service_vrps[1][:vrp].points += sub_service_vrps[0][:vrp].points.select{ |p| p.id == vehicle.start_point_id || p.id == vehicle.end_point_id }
        sub_service_vrps[1][:vrp].resolution_vehicle_limit += 1
      }
    end

    def self.dicho_level_coeff(service_vrp)
      balance = 0.66666
      level_approx = Math.log(service_vrp[:vrp].resolution_dicho_division_vec_limit / (service_vrp[:vrp].resolution_vehicle_limit || service_vrp[:vrp].vehicles.size).to_f, balance)
      service_vrp[:vrp].resolution_dicho_level_coeff = 2**(1 / (level_approx - service_vrp[:level]).to_f)
    end

    def self.set_config(service_vrp)
      # service_vrp[:vrp].resolution_batch_heuristic = true
      service_vrp[:vrp].restitution_allow_empty_result = true
      if service_vrp[:level]&.positive?
        service_vrp[:vrp].resolution_duration = if service_vrp[:vrp].resolution_duration && !service_vrp[:vrp].resolution_duration.zero?
                                                  (service_vrp[:vrp].resolution_duration / 2.66).to_i
                                                else
                                                  80000
                                                end
        service_vrp[:vrp].resolution_minimum_duration = if service_vrp[:vrp].resolution_minimum_duration && !service_vrp[:vrp].resolution_minimum_duration.zero?
                                                          (service_vrp[:vrp].resolution_minimum_duration / 2.66).to_i
                                                        else
                                                          70000
                                                        end
      end

      if service_vrp[:level] && service_vrp[:level] == 0
        dicho_level_coeff(service_vrp)
        service_vrp[:vrp].resolution_split_number = 1
        service_vrp[:vrp].resolution_total_split_number = 2
        service_vrp[:vrp].vehicles.each{ |vehicle|
          vehicle[:cost_fixed] = vehicle[:cost_fixed] && vehicle[:cost_fixed] > 0 ? vehicle[:cost_fixed] : 1e6
          if !vehicle[:cost_distance_multiplier] || vehicle[:cost_distance_multiplier].zero?
            vehicle[:cost_distance_multiplier] = 0.05
          end
        }
      end

      service_vrp[:vrp].resolution_init_duration = 90000 if service_vrp[:vrp].resolution_duration > 90000
      service_vrp[:vrp].resolution_vehicle_limit ||= service_vrp[:vrp][:vehicles].size
      if service_vrp[:vrp].vehicles.size > service_vrp[:vrp].resolution_dicho_division_vec_limit && service_vrp[:vrp].services.size > 100 &&
         service_vrp[:vrp].resolution_vehicle_limit > service_vrp[:vrp].resolution_dicho_division_vec_limit
        service_vrp[:vrp].resolution_init_duration = 1000
      else
        service_vrp[:vrp].resolution_init_duration = nil
      end
      service_vrp[:vrp].preprocessing_first_solution_strategy = ['parallel_cheapest_insertion'] # A bit slower than local_cheapest_insertion; however, returns better results on ortools-v7.

      service_vrp
    end

    def self.update_exlusion_cost(service_vrp)
      if !service_vrp[:level].zero?
        average_exclusion_cost = service_vrp[:vrp].services.collect{ |service| service.exclusion_cost }.sum / service_vrp[:vrp].services.size
        service_vrp[:vrp].services.each{ |service|
          service.exclusion_cost += average_exclusion_cost * (service_vrp[:vrp].resolution_dicho_level_coeff**service_vrp[:level] - 1)
        }
      end
    end

    def self.build_initial_routes(results)
      results.flat_map{ |result|
        next if result.nil?
        result[:routes].map{ |route|
          next if route.nil?
          mission_ids = route[:activities].map{ |activity| activity[:service_id] || activity[:rest_id] }.compact
          next if mission_ids.empty?
          Models::Route.new(
            vehicle: {
              id: route[:vehicle_id]
            },
            mission_ids: mission_ids
          )
        }
      }.compact
    end

    def self.remove_bad_skills(service_vrp, result)
      puts "------> remove_bad_skills"
      result[:routes].each{ |r|
        r[:activities].each{ |a|
          if a[:service_id]
            service = service_vrp[:vrp].services.find{ |s| s.id == a[:service_id] }
            vehicle = service_vrp[:vrp].vehicles.find{ |v| v.id == r[:vehicle_id] }
            if service && !service.skills.empty?
              if vehicle.skills.all?{ |xor_skills| (service.skills & xor_skills).size != service.skills.size }
                puts "Removed service #{a[:service_id]} from vehicle #{r[:vehicle_id]}"
                result[:unassigned] << a
                r[:activities].delete(a)
              end
            end
            # TODO: remove bad sticky?
          end
        }
      }
      puts "<----- remove_bad_skills"
    end

    def self.end_stage_insert_unassigned(service_vrp, result, job = nil)
      puts '--> dicho::third_stage'
      if !result[:unassigned].empty?
        puts "dicho::third_stage try to insert #{result[:unassigned].size} unassigned from #{service_vrp[:vrp].services.size} services"
        service_vrp[:vrp].routes = build_initial_routes([result])
        service_vrp[:vrp].resolution_init_duration = nil
        unassigned_services = service_vrp[:vrp].services.select{ |s| result[:unassigned].map{ |a| a[:service_id] }.include?(s.id) }
        unassigned_services_by_skills = unassigned_services.group_by{ |s| s.skills }
        # TODO: sort unassigned_services with no skill / sticky at the end
        unassigned_services_by_skills.each{ |skills, services|
          next if result[:unassigned].empty?
          vehicles_with_skills = skills.empty? ? service_vrp[:vrp].vehicles : service_vrp[:vrp].vehicles.select{ |v|
            v.skills.any?{ |or_skills| (skills & or_skills).size == skills.size }
          }
          sticky_vehicle_ids = unassigned_services.flat_map(&:sticky_vehicles).compact.map(&:id)
          # In case services has incoherent sticky and skills, sticky is the winner
          unless sticky_vehicle_ids.empty?
            vehicles_with_skills = service_vrp[:vrp].vehicles.select{ |v| sticky_vehicle_ids.include?(v.id) }
          end

          # Shuffle so that existing routes will be distributed randomly
          # Otherwise we might have a sub_vrp with 6 existing routes (no empty routes) and
          # hundreds of services which makes it very hard to insert a point
          # With shuffle we distribute the existing routes accross all sub-vrps we create
          vehicles_with_skills.shuffle!

          #TODO: Here we launch the optim of a single skill however, it make sense to include the vehicles without skills
          #(especially the ones with existing routes) in the sub_vrp because that way optim can move poits between vehicles
          #and serve an unserviced point with skills.

          #TODO: We do not consider the geographic closeness/distance of routes and points.
          #This might be the reason why sometimes we have solutions with long detours.
          #However, it is not very easy to find a generic and effective way.

          sub_results = []
          vehicle_count = skills.empty? && !service_vrp[:vrp].routes.empty? ? [service_vrp[:vrp].routes.size, 6].min : 3
          vehicles_with_skills.each_slice(vehicle_count) do |vehicles|
            remaining_service_ids = result[:unassigned].map{ |u| u[:service_id] } & services.map(&:id)
            next if remaining_service_ids.empty?
            assigned_service_ids = result[:routes].select{ |r| vehicles.map(&:id).include?(r[:vehicle_id]) }.flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact

            sub_service_vrp = SplitClustering.build_partial_service_vrp(service_vrp, remaining_service_ids + assigned_service_ids, vehicles.map(&:id))
            sub_service_vrp[:vrp].vehicles.each{ |vehicle|
              vehicle[:cost_fixed] = vehicle[:cost_fixed] && vehicle[:cost_fixed] > 0 ? vehicle[:cost_fixed] : 1e6
              if !vehicle[:cost_distance_multiplier] || vehicle[:cost_distance_multiplier].zero?
                vehicle[:cost_distance_multiplier] = 0.05
              end
            }
            rate_vehicles = vehicles.size / vehicles_with_skills.size.to_f
            rate_services = services.size / unassigned_services.size.to_f
            if sub_service_vrp[:vrp].resolution_duration
              sub_service_vrp[:vrp].resolution_duration = [(service_vrp[:vrp].resolution_duration / 3.99 * rate_vehicles * rate_services).to_i, 150].max
            end
            if sub_service_vrp[:vrp].resolution_minimum_duration
              sub_service_vrp[:vrp].resolution_minimum_duration = [(service_vrp[:vrp].resolution_minimum_duration / 3.99 * rate_vehicles * rate_services).to_i, 100].max
            end
            # sub_service_vrp[:vrp].resolution_vehicle_limit = sub_service_vrp[:vrp].vehicles.size
            sub_service_vrp[:vrp].restitution_allow_empty_result = true
            result_loop = OptimizerWrapper.solve([sub_service_vrp], job, nil)
            result[:elapsed] += result_loop[:elapsed] if result_loop && result_loop[:elapsed]

            # Initial routes can be refused... check unassigned size before take into account solution
            if result_loop && remaining_service_ids.size >= result_loop[:unassigned].size
              remove_bad_skills(sub_service_vrp, result_loop)
              result[:unassigned].delete_if{ |unassigned_activity|
                result_loop[:routes].any?{ |route|
                  route[:activities].any?{ |activity| activity[:service_id] == unassigned_activity[:service_id] }
                }
              }
              # result[:unassigned] |= result_loop[:unassigned] # Cannot use | operator because :type field not always present...
              result[:unassigned].delete_if{ |activity| result_loop[:unassigned].map{ |a| a[:service_id] }.include?(activity[:service_id]) }
              result[:unassigned] += result_loop[:unassigned]
              result[:routes].delete_if{ |old_route|
                result_loop[:routes].map{ |r| r[:vehicle_id] }.include?(old_route[:vehicle_id])
              }
              result[:routes] += result_loop[:routes]
              # TODO: merge costs, total_infos...
              sub_results << result_loop
            end
          end
          new_routes = build_initial_routes(sub_results)
          vehicle_ids = sub_results.flat_map{ |r| r[:routes].map{ |route| route[:vehicle_id] } }
          service_vrp[:vrp].routes.delete_if{ |r| vehicle_ids.include?(r.vehicle.id) }
          service_vrp[:vrp].routes += new_routes
        }
      end
      puts '<-- dicho::third_stage'
      result
    end

    def self.split_vehicles(vrp, services_by_cluster)
      puts "--> dicho::split_vehicles #{vrp.vehicles.size}"
      services_skills_by_clusters = services_by_cluster.map{ |services|
        services.map{ |s| s.skills.empty? ? nil : s.skills.uniq.sort }.compact.uniq
      }
      puts "services_skills_by_clusters #{services_skills_by_clusters}"
      vehicles_by_clusters = [[], []]
      vrp.vehicles.each{ |v|
        cluster_index = nil
        # Vehicle skills is an array of array of strings
        unless v.skills.empty?
          # If vehicle has skills which match with service skills in only one cluster, prefer this cluster for this vehicle
          preferered_index = []
          services_skills_by_clusters.each_with_index{ |services_skills, index|
            preferered_index << index if services_skills.any?{ |skills| v.skills.any?{ |v_skills| (skills & v_skills).size == skills.size } }
          }
          cluster_index = preferered_index.first if preferered_index.size == 1
        end
        # TODO: prefer cluster with sticky vehicle
        # TODO: avoid to prefer always same cluster
        if cluster_index &&
           ((vehicles_by_clusters[1].size - 1) / services_by_cluster[1].size > (vehicles_by_clusters[0].size + 1) / services_by_cluster[0].size ||
           (vehicles_by_clusters[1].size + 1) / services_by_cluster[1].size < (vehicles_by_clusters[0].size - 1) / services_by_cluster[0].size)
           cluster_index = nil
        end
        if vehicles_by_clusters[0].empty? || vehicles_by_clusters[1].empty?
          cluster_index ||= vehicles_by_clusters[0].size <= vehicles_by_clusters[1].size ? 0 : 1
        else
          cluster_index ||= services_by_cluster[0].size / vehicles_by_clusters[0].size >= services_by_cluster[1].size / vehicles_by_clusters[1].size ? 0 : 1
        end
        vehicles_by_clusters[cluster_index] << v
      }

      if vehicles_by_clusters.any?(&:empty?)
        empty_side = vehicles_by_clusters.select(&:empty?)[0]
        nonempty_side = vehicles_by_clusters.select(&:any?)[0]

        # Move a vehicle from the skill group with most vehicles (from nonempty side to empty side)
        empty_side << nonempty_side.delete(nonempty_side.group_by{ |v| v.skills.uniq.sort }.to_a.max_by{ |vec_group| vec_group[1].size }.last.first)
      end

      puts "<-- dicho::split_vehicles #{vehicles_by_clusters.map(&:size)}"
      vehicles_by_clusters
    end

    def self.split(service_vrp, job = nil, &block)
      puts '--> dicho::split'
      vrp = service_vrp[:vrp]
      vrp.resolution_vehicle_limit ||= vrp.vehicles.size
      options = { max_iterations: 100, restarts: 5, cut_symbol: :duration, last_iteration_balance_rate: 0.0 }
      services_by_cluster = SplitClustering.split_balanced_kmeans(service_vrp, 2, options, &block)
      split_service_vrps = []
      if services_by_cluster.size == 2
        # Kmeans return 2 vrps
        dicosplitvec = Time.now
        vehicles_by_cluster = split_vehicles(vrp, [services_by_cluster.first[:vrp].services, services_by_cluster.second[:vrp].services])
        puts "DICHO SPLIT VEHICLE   ---   #{Time.now - dicosplitvec}"
        if vehicles_by_cluster[1].size > vehicles_by_cluster[0].size
          services_by_cluster.reverse
          vehicles_by_cluster.reverse
        end
        services_by_cluster.each_with_index{ |sub_service_vrp, i|
          sub_service_vrp[:vrp] = SplitClustering.build_partial_service_vrp(service_vrp, sub_service_vrp[:vrp].services.map(&:id), vehicles_by_cluster[i].map(&:id))[:vrp]
          # TODO: à cause de la grande disparité du split_vehicles par skills, on peut rapidement tomber à 1...
          sub_service_vrp[:vrp].resolution_vehicle_limit = [sub_service_vrp[:vrp].vehicles.size, vrp.vehicles.empty? ? 0 : (sub_service_vrp[:vrp].vehicles.size / vrp.vehicles.size.to_f * vrp.resolution_vehicle_limit).ceil].min
          sub_service_vrp[:vrp].resolution_split_number += i
          sub_service_vrp[:vrp].resolution_total_split_number += 1

          split_service_vrps << {
            service: service_vrp[:service],
            vrp: sub_service_vrp[:vrp],
            level: service_vrp[:level] + 1
          }
        }
      else
        raise 'Incorrect split size with kmeans' if services_by_cluster.size > 2
        # Kmeans return 1 vrp
        split_service_vrps << service_vrp
      end
      SplitClustering.output_clusters(split_service_vrps) if service_vrp[:vrp][:debug_output_clusters]

      split_service_vrps
    end
  end
end
