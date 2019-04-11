$(document).ready(function () {
	radiant.call('tower_defense:get_service','game')
		.done(function (e) {
			App.gameView.addView(App.TowerDefenseGameStateWindow, { uri: e.result })
		})
		.fail(function (e) {
			console.log('error getting game service')
			console.dir(e)
		});
});

App.TowerDefenseGameStateWindow = App.View.extend({
	templateName: 'gameStateWindow',
	uriProperty: 'model',
	closeOnEsc: false,

	components: {
		'wave_controller': {}
	},

	didInsertElement: function () {
		var self = this;

		$('#gameStateWindow')
			.draggable()

	},

	willDestroyElement: function () {
		this._super();
	},
});
