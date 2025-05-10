$(document).ready(function() {
    window.addEventListener('message', handleMessage);
});

const config = {
    respawnHoldTime: 5000, 
    progressUpdateInterval: 50, 
    emsCooldown: 300, // Default 5 minutes, will be overridden by server config
    billCost: 2000 // Default bill cost, will be overridden by server config
};

let state = {
    timeRemaining: 0,
    isCritical: false,
    isSpaceHeld: false,
    emsCooldown: false,
    respawnStartTime: 0,
    respawnTimerId: null,
    emsTimerId: null,
    emsTimeRemaining: 300
};

function formatTime(seconds) {
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
}



function handleMessage(event) {
    const data = event.data;

    switch (data.action) {
        case 'initState':
            state.isSpaceHeld = false;
            if (state.respawnTimerId) {
                clearInterval(state.respawnTimerId);
                state.respawnTimerId = null;
            }
            if (state.emsTimerId) {
                clearInterval(state.emsTimerId);
                state.emsTimerId = null;
            }
            $('.key').removeClass('pressed');
            $('.progress-container').css({
                'display': 'none',
                'visibility': 'hidden',
                'opacity': '0'
            });

            if (data.emsCooldown) {
                config.emsCooldown = data.emsCooldown;
            }
            if (data.billCost) {
                config.billCost = data.billCost;
                $('.time-value').text(`$${data.billCost}`);
            }
            if (data.critical) {
                setCriticalState(true);
            }
            if (data.show) {
                $('body').fadeIn();
            }
            if (typeof data.time === 'number') {
                updateTimer(data.time);
            }
            break;

        case 'show':
            state.isSpaceHeld = false;
            if (state.respawnTimerId) {
                clearInterval(state.respawnTimerId);
                state.respawnTimerId = null;
            }
            $('.key').removeClass('pressed');
            $('.progress-container').css({
                'display': 'none',
                'visibility': 'hidden',
                'opacity': '0'
            });
            $('body').fadeIn();
            break;

        case 'hide':
            if (state.emsTimerId) {
                clearInterval(state.emsTimerId);
                state.emsTimerId = null;
            }
            state.emsCooldown = false;
            state.emsTimeRemaining = config.emsCooldown;
            $('body').fadeOut();
            break;

        case 'updateTimer':
            updateTimer(data.time);
            break;

        case 'setCritical':
            if (data.emsCooldown) {
                config.emsCooldown = data.emsCooldown;
            }
            setCriticalState(data.critical);
            break;

        case 'setStatus':
            setStatus(data.status);
            break;
    }
}

$(document).ready(() => {
    window.addEventListener('message', handleMessage);

    $(document).on('keydown', function(e) {
        
        if (e.key === ' ' || e.keyCode === 32) {            
            if (state.isCritical && !state.isSpaceHeld) {
                state.isSpaceHeld = true;
                const spaceKey = $('.key:contains("Space")');
                spaceKey.addClass('pressed');
                startRespawnTimer();
            }
            e.preventDefault();
        }
        
        if ((e.key === 'e' || e.keyCode === 69) && !state.isCritical && !state.emsCooldown) {
            const eKey = $('#e-key');
            eKey.addClass('pressed');
            $.post('https://qb-ambulancejob/callEms', JSON.stringify({}));

        }
    });

    $(document).on('keyup', function(e) {
        if (e.key === ' ' || e.keyCode === 32) {
            state.isSpaceHeld = false;
            const spaceKey = $('.key:contains("Space")');
            spaceKey.removeClass('pressed');
            cancelRespawnTimer();
            e.preventDefault();
        }
        
        if (e.key === 'e' || e.keyCode === 69) {
            const eKey = $('#e-key');
            eKey.removeClass('pressed');

        }
    });


});

function updateTimer(time) {
    state.timeRemaining = time;
    if (state.isCritical) {
        $('#timer').text('00:00');
    } else {
        $('#timer').text(formatTime(Math.max(0, time)));
    }
}

function updateEmsTimer() {
    if (!state.emsCooldown || state.emsTimeRemaining <= 0) {
        if (state.emsTimerId) {
            clearInterval(state.emsTimerId);
            state.emsTimerId = null;
        }
        return;
    }

    const minutes = Math.floor(state.emsTimeRemaining / 60);
    const seconds = state.emsTimeRemaining % 60;
    $('#ems-instruction').html(`
        <span id="ems-text">EMS have ${minutes}:${seconds.toString().padStart(2, '0')} to accept the call</span>
    `).addClass('ems-waiting');

    state.emsTimeRemaining--;
}

function setStatus(status) {
    $('.initial-text').remove();
    
    if (status === 'no_ems') {
        $('#ems-instruction').html(`
            <span id="ems-text">There is no active EMS</span>
        `).addClass('ems-waiting');
        return;
    }
    
    if (status === 'ems_called') {
        state.emsCooldown = true;
        state.emsTimeRemaining = config.emsCooldown;
        
        if (state.emsTimerId) {
            clearInterval(state.emsTimerId);
        }
        state.emsTimerId = setInterval(updateEmsTimer, 1000);
        
    } else if (status === 'ems_accepted') {
        if (state.emsTimerId) {
            clearInterval(state.emsTimerId);
            state.emsTimerId = null;
        }
        $('#ems-instruction').html(`
            <span id="ems-text">EMS are on their way</span>
        `).addClass('ems-waiting');
    }
}

function setCriticalState(critical) {
    state.isCritical = critical;
    
    if (critical) {
        $('#status-text').html('You are in <span class="critical">critical</span> condition');
        $('#timer').text('00:00');
        $('#timer').addClass('critical');
        $('#ems-instruction').addClass('hidden');
        $('#respawn-instruction').addClass('active');
        state.timeRemaining = 0;
    } else {
        $('#status-text').html('You are <span class="injured">injured</span>');
        $('#timer').removeClass('critical');
        $('#ems-instruction').removeClass('hidden');
        $('#respawn-instruction').removeClass('active');
        $('.progress-container').css({
            'display': 'none',
            'visibility': 'hidden',
            'opacity': '0'
        });
    }
}

function startRespawnTimer() {
    if (!state.isCritical || !state.isSpaceHeld) {
        return;
    }

    $('.progress-container').css({
        'display': 'block',
        'visibility': 'visible',
        'opacity': '1'
    });
    
    $('#respawn-progress').css('width', '0');
    
    state.respawnStartTime = Date.now();
    
    if (state.respawnTimerId) {
        clearInterval(state.respawnTimerId);
        state.respawnTimerId = null;
    }
    
    state.respawnTimerId = setInterval(() => {
        if (!state.isSpaceHeld) {
            cancelRespawnTimer();
            return;
        }
        
        const elapsedTime = Date.now() - state.respawnStartTime;
        const progress = Math.min((elapsedTime / config.respawnHoldTime) * 100, 100);
        
        $('#respawn-progress').css('width', `${progress}%`);
        
        if (progress >= 100) {
            $.post('https://qb-ambulancejob/respawnPlayer', JSON.stringify({}));
            cancelRespawnTimer();
        }
    }, config.progressUpdateInterval);
}

function cancelRespawnTimer() {
    if (state.respawnTimerId) {
        clearInterval(state.respawnTimerId);
        state.respawnTimerId = null;
        
        $('#respawn-progress').css('width', '0');
        $('.progress-container').css({
            'display': 'none',
            'visibility': 'hidden',
            'opacity': '0'
        });

    }
}
