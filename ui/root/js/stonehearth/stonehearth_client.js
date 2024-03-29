$(document).ready(function(){
   App.stonehearthClient.doCommand = function(entity, player_id, command) {
      var self = this;
      if (!command.enabled) {
         return;
      }
      var event_name = '';

      if (command.action == 'fire_event') {
         // xxx: error checking would be nice!!
         var e = {
            entity : entity,
            event_data : command.event_data,
            player_id : player_id
         };
         $(top).trigger(command.event_name, e);

         event_name = command.event_name.toString().replace(':','_')

      } else if (command.action == 'call') {
         var uri = ((typeof entity) == 'object') ? entity.__self : entity;
         if (!uri) return;
         var args = [uri];
         if (command.args) {
            radiant.each(command.args, function(_, v) {
               args.push(v);
            });
         }

         var play_sound = function(sound_data) {
            sound_data = radiant.shallow_copy(sound_data);
            if (Array.isArray(sound_data.track)) {
               sound_data.track = sound_data.track[Math.floor(Math.random() * sound_data.track.length)];
            }
            radiant.call('radiant:play_sound', sound_data );
         };

         if (command.object) {
            //if the command is "repeating" then call it again when done
            radiant.call_objv(command.object, command['function'], args)
               .deferred.done(function(response){
                  if (command.sound_on_complete) {
                     play_sound( command.sound_on_complete );
                  }
                  if (command.repeating == true) {
                     self.doCommand(entity, player_id, command);
                  }
               });
         } else {
            radiant.callv(command['function'], args)
               .deferred.done(function(response) {
                  if (command.sound_on_complete) {
                     play_sound( command.sound_on_complete );
                  }
               })
               .fail(function(response) {
                  if (response.message) {
                     $(document).trigger('td_player_alert', {
                        message: i18n.t(response.message, response)
                     });
                  }
               });
         }

         event_name = command['function'].toString().replace(':','_')

      } else {
         throw "unknown command.action " + command.action
      }
   }
});